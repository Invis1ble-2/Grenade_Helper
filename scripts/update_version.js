import fs from 'fs';
import path from 'path';
import https from 'https';
import { execSync } from 'child_process';

// === 配置区域 ===
const OWNER = 'Invis1ble-2';
const REPO = 'Grenade_Helper';
// 【重要】部署完 Zeabur 后，把这里改成你的真实域名
const ZEABUR_URL = 'https://cdn.grenade-helper.top:8443';

// 当前脚本服务的平台
const PLATFORM = 'android';

const ADMIN_SECRET = process.env.ADMIN_SECRET;
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;

if (!ADMIN_SECRET) {
  console.error("Error: ADMIN_SECRET is missing.");
  process.exit(1);
}
// 私有仓库必须有 Token
if (!GITHUB_TOKEN) {
  console.error("Error: GITHUB_TOKEN is missing (required for private repo).");
  process.exit(1);
}

// 简单的 fetch 封装
function fetchJson(url, headers = {}) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Node.js', ...headers } }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try { resolve(JSON.parse(data)); } catch { reject('JSON Parse Error'); }
        } else {
          if (res.statusCode === 404) resolve(null);
          else reject(`Request failed: ${res.statusCode} ${url}`);
        }
      });
    }).on('error', reject);
  });
}

async function main() {
  try {
    console.log(`Fetching release info for ${OWNER}/${REPO}...`);

    // 1. 获取 GitHub Release (带 Token)
    const release = await fetchJson(
      `https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
      { 'Authorization': `token ${GITHUB_TOKEN}` }
    );

    if (!release) throw new Error("Could not fetch release info. Check Token/Permissions.");

    // 2. 获取 Zeabur 当前版本
    const currentStatus = await fetchJson(`${ZEABUR_URL}/update/${PLATFORM}`).catch(() => null);
    const versionName = release.tag_name.replace(/^v/, '');

    // 3. 计算 VersionCode
    let versionCode = 0;
    const bodyText = release.body || '';
    // 尝试从 release body 提取 "vc: 12" 或 "versionCode=12" 这样的明确格式
    // 使用 \b 单词边界并要求必须有 : 或 = 分隔符，避免从其他文本误匹配
    const vcMatch = bodyText.match(/\b(?:vc|versionCode)\s*[:=]\s*(\d+)/i);

    if (vcMatch) {
      versionCode = parseInt(vcMatch[1], 10);
    } else {
      // 自动递增逻辑
      if (currentStatus && currentStatus.versionName === versionName) {
        versionCode = currentStatus.versionCode;
      } else {
        versionCode = (currentStatus ? currentStatus.versionCode : 0) + 1;
      }
    }

    // 检查是否重复
    if (currentStatus && currentStatus.versionCode === versionCode && currentStatus.versionName === versionName) {
      console.log("Version matches. Skipping.");
      return;
    }

    // 4. 筛选并下载 APK (私有仓库 + v8a 适配)
    console.log(`Looking for 'arm64-v8a' apk...`);

    // 【关键】筛选 arm64-v8a 且是 apk
    const apkAsset = release.assets.find(asset =>
      asset.name.includes('arm64-v8a') && asset.name.endsWith('.apk')
    );

    if (!apkAsset) {
      console.error("Assets found:", release.assets.map(a => a.name));
      throw new Error("Target APK (arm64-v8a) not found in release!");
    }

    const tempApkPath = path.join(process.cwd(), `temp_${apkAsset.name}`);

    // 【关键】私有仓库下载必须使用 API URL (asset.url) + Accept header
    // 不能使用 browser_download_url
    console.log(`Downloading ${apkAsset.name} from private repo...`);

    const downloadCmd = [
      `curl -L`,
      `-H "Authorization: token ${GITHUB_TOKEN}"`, // 认证
      `-H "Accept: application/octet-stream"`,     // 告诉 GitHub 我们要二进制流
      `-o "${tempApkPath}"`,
      `"${apkAsset.url}"`                           // 使用 API URL
    ].join(' ');

    execSync(downloadCmd);

    // 验证文件大小
    const stats = fs.statSync(tempApkPath);
    if (stats.size < 1000) { // 如果文件小于 1KB，很可能是下载到了报错 JSON
      const content = fs.readFileSync(tempApkPath, 'utf8');
      console.error("Download content preview:", content);
      throw new Error("Downloaded file is too small, likely an auth error.");
    }

    // 5. 上传到 Zeabur
    console.log(`Uploading to Zeabur (Platform: ${PLATFORM})...`);

    const cleanContent = bodyText.replace(/(?:vc|versionCode)\s*[:=]?\s*(\d+)/ig, '').trim();

    // 检测是否需要强制更新 (支持 force: true, forceUpdate: true 等格式)
    const forceMatch = bodyText.match(/\b(?:force|forceUpdate)\s*[:=]\s*(true|1|yes)/i);
    const forceUpdate = forceMatch ? 'true' : 'false';

    // 传递 platform 参数
    const uploadCmd = [
      `curl -X POST "${ZEABUR_URL}/upload"`,
      `-H "Authorization: ${ADMIN_SECRET}"`,
      `-F "file=@${tempApkPath}"`,
      `-F "versionCode=${versionCode}"`,
      `-F "versionName=${versionName}"`,
      `-F "content=${cleanContent || 'Update'}"`,
      `-F "platform=${PLATFORM}"`,
      `-F "forceUpdate=${forceUpdate}"`
    ].join(' ');

    execSync(uploadCmd);
    console.log("Upload successful!");

    fs.unlinkSync(tempApkPath);

  } catch (error) {
    console.error("Workflow failed:", error);
    process.exit(1);
  }
}

main();