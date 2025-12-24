import fs from 'fs';
import path from 'path';
import https from 'https';
import { execSync } from 'child_process';

// === 配置区域 ===
const OWNER = 'Invis1ble-2';
const REPO = 'Grenade_Helper';

// 【双服务器配置】同时向两个服务器上传，确保新旧版本App都能获取更新
const SERVER_URLS = [
  'https://cdn.grenade-helper.top:8443',  // 新服务器（日本VPS）
  'https://app-grenade-helper.zeabur.app' // 旧服务器（Zeabur，兼容旧版App）
];

// 主服务器（用于检查版本）
const PRIMARY_URL = SERVER_URLS[0];

// 支持的平台列表
const SUPPORTED_PLATFORMS = ['android', 'windows', 'ios'];

// 从命令行参数获取平台，默认 android
const PLATFORM = process.argv[2] || 'android';

if (!SUPPORTED_PLATFORMS.includes(PLATFORM)) {
  console.error(`Error: Unsupported platform '${PLATFORM}'. Supported: ${SUPPORTED_PLATFORMS.join(', ')}`);
  process.exit(1);
}

console.log(`=== Running for platform: ${PLATFORM} ===`);

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

    // 2. 获取主服务器当前版本
    const currentStatus = await fetchJson(`${PRIMARY_URL}/update/${PLATFORM}`).catch(() => null);
    const versionName = release.tag_name.replace(/^v/, '');

    // 3. 计算 VersionCode
    let versionCode = 0;
    const bodyText = release.body || '';
    // 尝试从 release body 提取 "vc: 12" 这样的文本
    const vcMatch = bodyText.match(/(?:vc|versionCode)\s*[:=]?\s*(\d+)/i);

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

    // 4. 根据平台筛选对应的安装包
    /**
     * 根据平台查找对应的 asset
     * @param {Array} assets - release assets 列表
     * @param {string} platform - 目标平台
     * @returns {Object|null} asset 对象
     */
    function findAssetForPlatform(assets, platform) {
      switch (platform) {
        case 'android':
          // Android: 筛选 arm64-v8a 且是 apk
          return assets.find(asset =>
            asset.name.includes('arm64-v8a') && asset.name.endsWith('.apk')
          );
        case 'windows':
          // Windows: 优先 .exe 安装程序，其次 .msix
          return assets.find(asset => asset.name.endsWith('.exe')) ||
            assets.find(asset => asset.name.endsWith('.msix'));
        case 'ios':
          // iOS: .ipa 文件
          return assets.find(asset => asset.name.endsWith('.ipa'));
        default:
          return null;
      }
    }

    console.log(`Looking for ${PLATFORM} release asset...`);

    const targetAsset = findAssetForPlatform(release.assets, PLATFORM);

    if (!targetAsset) {
      console.error("Available assets:", release.assets.map(a => a.name));
      throw new Error(`Target asset for platform '${PLATFORM}' not found in release!`);
    }

    const tempFilePath = path.join(process.cwd(), `temp_${targetAsset.name}`);

    // 【关键】私有仓库下载必须使用 API URL (asset.url) + Accept header
    // 不能使用 browser_download_url
    console.log(`Downloading ${targetAsset.name} from private repo...`);

    const downloadCmd = [
      `curl -L`,
      `-H "Authorization: token ${GITHUB_TOKEN}"`, // 认证
      `-H "Accept: application/octet-stream"`,     // 告诉 GitHub 我们要二进制流
      `-o "${tempFilePath}"`,
      `"${targetAsset.url}"`                        // 使用 API URL
    ].join(' ');

    execSync(downloadCmd);

    // 验证文件大小
    const stats = fs.statSync(tempFilePath);
    if (stats.size < 1000) { // 如果文件小于 1KB，很可能是下载到了报错 JSON
      const content = fs.readFileSync(tempFilePath, 'utf8');
      console.error("Download content preview:", content);
      throw new Error("Downloaded file is too small, likely an auth error.");
    }

    // 5. 上传到所有服务器（双服务器同步）
    const cleanContent = bodyText.replace(/(?:vc|versionCode)\s*[:=]?\s*(\d+)/ig, '').trim();

    for (const serverUrl of SERVER_URLS) {
      console.log(`Uploading to ${serverUrl} (Platform: ${PLATFORM})...`);

      const uploadCmd = [
        `curl -X POST "${serverUrl}/upload"`,
        `-H "Authorization: ${ADMIN_SECRET}"`,
        `-F "file=@${tempFilePath}"`,
        `-F "versionCode=${versionCode}"`,
        `-F "versionName=${versionName}"`,
        `-F "content=${cleanContent || 'Update'}"`,
        `-F "platform=${PLATFORM}"`
      ].join(' ');

      try {
        execSync(uploadCmd);
        console.log(`✓ Upload to ${serverUrl} successful!`);
      } catch (err) {
        console.error(`✗ Upload to ${serverUrl} failed:`, err.message);
        // 继续上传到下一个服务器，不中断流程
      }
    }

    console.log("All servers sync completed!");

    fs.unlinkSync(tempFilePath);

  } catch (error) {
    console.error("Workflow failed:", error);
    process.exit(1);
  }
}

main();