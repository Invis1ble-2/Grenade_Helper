#include "flutter_window.h"

#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

std::optional<int> GetEncodableInt(const flutter::EncodableMap& map,
                                   const char* key) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return static_cast<int>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(*value);
  }
  return std::nullopt;
}

bool GetEncodableBool(const flutter::EncodableMap& map, const char* key,
                      bool default_value = false) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return default_value;
  }
  if (const auto* value = std::get_if<bool>(&iterator->second)) {
    return *value;
  }
  return default_value;
}

bool IsVirtualKeyPressed(int virtual_key) {
  return (::GetAsyncKeyState(virtual_key) & 0x8000) != 0;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  navigation_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "grenade_helper/windows_navigation",
          &flutter::StandardMethodCodec::GetInstance());
  navigation_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleNavigationMethodCall(call, std::move(result));
      });

  // Register the callback for sub-windows created by desktop_multi_window
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  navigation_channel_.reset();
  ClearNavigationBindings();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
  case WM_FONTCHANGE:
    flutter_controller_->engine()->ReloadSystemFonts();
    break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HandleNavigationMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method_name = method_call.method_name();

  if (method_name == "setNavigationBindings") {
    ClearNavigationBindings();

    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("invalid_args", "Expected a map of navigation bindings.");
      return;
    }

    for (const auto& entry : *args) {
      const auto* direction = std::get_if<std::string>(&entry.first);
      const auto* payload = std::get_if<flutter::EncodableMap>(&entry.second);
      if (direction == nullptr || payload == nullptr) {
        continue;
      }

      NavigationBinding* binding = GetBindingForDirection(*direction);
      if (binding == nullptr) {
        continue;
      }

      binding->virtual_key = GetEncodableInt(*payload, "virtualKey");
      binding->requires_alt = GetEncodableBool(*payload, "requiresAlt");
      binding->requires_ctrl = GetEncodableBool(*payload, "requiresCtrl");
      binding->requires_shift = GetEncodableBool(*payload, "requiresShift");
    }

    result->Success();
    return;
  }

  if (method_name == "readNavigationState") {
    result->Success(flutter::EncodableValue(ReadNavigationState()));
    return;
  }

  if (method_name == "clearNavigationBindings") {
    ClearNavigationBindings();
    result->Success();
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::ClearNavigationBindings() {
  up_binding_ = NavigationBinding{};
  down_binding_ = NavigationBinding{};
  left_binding_ = NavigationBinding{};
  right_binding_ = NavigationBinding{};
}

FlutterWindow::NavigationBinding* FlutterWindow::GetBindingForDirection(
    const std::string& direction) {
  if (direction == "up") {
    return &up_binding_;
  }
  if (direction == "down") {
    return &down_binding_;
  }
  if (direction == "left") {
    return &left_binding_;
  }
  if (direction == "right") {
    return &right_binding_;
  }
  return nullptr;
}

const FlutterWindow::NavigationBinding* FlutterWindow::GetBindingForDirection(
    const std::string& direction) const {
  if (direction == "up") {
    return &up_binding_;
  }
  if (direction == "down") {
    return &down_binding_;
  }
  if (direction == "left") {
    return &left_binding_;
  }
  if (direction == "right") {
    return &right_binding_;
  }
  return nullptr;
}

flutter::EncodableMap FlutterWindow::ReadNavigationState() const {
  flutter::EncodableMap state;
  for (const auto* direction : {"up", "down", "left", "right"}) {
    const NavigationBinding* binding = GetBindingForDirection(direction);
    state[flutter::EncodableValue(direction)] =
        flutter::EncodableValue(binding != nullptr && IsBindingPressed(*binding));
  }
  return state;
}

bool FlutterWindow::IsBindingPressed(const NavigationBinding& binding) const {
  if (!binding.virtual_key.has_value()) {
    return false;
  }

  if (!IsVirtualKeyPressed(*binding.virtual_key)) {
    return false;
  }

  if (binding.requires_alt && !IsVirtualKeyPressed(VK_MENU)) {
    return false;
  }
  if (binding.requires_ctrl && !IsVirtualKeyPressed(VK_CONTROL)) {
    return false;
  }
  if (binding.requires_shift && !IsVirtualKeyPressed(VK_SHIFT)) {
    return false;
  }

  return true;
}
