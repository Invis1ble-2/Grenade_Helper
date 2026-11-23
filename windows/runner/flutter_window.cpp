#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kHotkeyTimerId = 1001;
constexpr UINT kIdleHotkeyPollIntervalMs = 50;
constexpr UINT kActiveHotkeyPollIntervalMs = 16;

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

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool is_overlay)
    : project_(project), is_overlay_(is_overlay) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  if (is_overlay_) {
    overlay_window_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(),
            "grenade_helper/overlay_window",
            &flutter::StandardMethodCodec::GetInstance());
    overlay_window_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleOverlayWindowMethodCall(call, std::move(result));
        });
  } else {
    navigation_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(),
            "grenade_helper/windows_navigation",
            &flutter::StandardMethodCodec::GetInstance());
    navigation_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleHotkeyMethodCall(call, std::move(result));
        });
  }

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  if (!is_overlay_) {
    flutter_controller_->engine()->SetNextFrameCallback(
        [&]() { this->Show(); });
  }
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  StopHotkeyTimer();
  overlay_window_channel_.reset();
  navigation_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  ClearHotkeyBindings();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_TIMER:
      if (wparam == kHotkeyTimerId) {
        PollHotkeys();
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HandleOverlayWindowMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method_name = method_call.method_name();
  HWND hwnd = GetHandle();

  if (method_name == "showNoActivate") {
    if (hwnd != nullptr) {
      ::ShowWindow(hwnd, SW_SHOWNOACTIVATE);
      ::SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
    result->Success();
    return;
  }

  if (method_name == "hide") {
    if (hwnd != nullptr) {
      ::ShowWindow(hwnd, SW_HIDE);
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::HandleHotkeyMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method_name = method_call.method_name();

  if (method_name == "setHotkeyBindings") {
    ClearHotkeyBindings();

    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("invalid_args", "Expected a map of hotkey bindings.");
      return;
    }

    for (const auto& entry : *args) {
      const auto* action = std::get_if<std::string>(&entry.first);
      const auto* payload = std::get_if<flutter::EncodableMap>(&entry.second);
      if (action == nullptr || payload == nullptr) {
        continue;
      }

      HotkeyBinding binding;
      binding.virtual_key = GetEncodableInt(*payload, "virtualKey");
      binding.requires_alt = GetEncodableBool(*payload, "requiresAlt");
      binding.requires_ctrl = GetEncodableBool(*payload, "requiresCtrl");
      binding.requires_shift = GetEncodableBool(*payload, "requiresShift");
      binding.requires_meta = GetEncodableBool(*payload, "requiresMeta");
      binding.core = GetEncodableBool(*payload, "core");
      binding.repeat = GetEncodableBool(*payload, "repeat");
      hotkey_bindings_[*action] = binding;
      last_pressed_state_[*action] = false;
    }

    UpdateHotkeyTimer();
    result->Success();
    return;
  }

  if (method_name == "setOverlayHotkeysEnabled") {
    const auto* enabled = std::get_if<bool>(method_call.arguments());
    if (enabled == nullptr) {
      result->Error("invalid_args", "Expected a bool.");
      return;
    }

    if (overlay_hotkeys_enabled_ != *enabled) {
      overlay_hotkeys_enabled_ = *enabled;
      if (!overlay_hotkeys_enabled_) {
        for (auto& [action, was_pressed] : last_pressed_state_) {
          auto it = hotkey_bindings_.find(action);
          if (it != hotkey_bindings_.end() && !it->second.core && was_pressed) {
            was_pressed = false;
            EmitHotkeyEvent(action, false);
          }
        }
      }
      UpdateHotkeyTimer();
    }

    result->Success();
    return;
  }

  if (method_name == "clearHotkeyBindings") {
    ClearHotkeyBindings();
    result->Success();
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::ClearHotkeyBindings() {
  StopHotkeyTimer();
  hotkey_bindings_.clear();
  last_pressed_state_.clear();
  consumed_primary_keys_.clear();
}

void FlutterWindow::UpdateHotkeyTimer() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || hotkey_bindings_.empty()) {
    StopHotkeyTimer();
    return;
  }
  const UINT interval_ms = overlay_hotkeys_enabled_
                               ? kActiveHotkeyPollIntervalMs
                               : kIdleHotkeyPollIntervalMs;
  ::SetTimer(hwnd, kHotkeyTimerId, interval_ms, nullptr);
  hotkey_timer_active_ = true;
}

void FlutterWindow::StopHotkeyTimer() {
  if (!hotkey_timer_active_) return;
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    ::KillTimer(hwnd, kHotkeyTimerId);
  }
  hotkey_timer_active_ = false;
}

void FlutterWindow::PollHotkeys() {
  if (!navigation_channel_ || hotkey_bindings_.empty()) return;

  for (auto it = consumed_primary_keys_.begin();
       it != consumed_primary_keys_.end();) {
    if (!IsVirtualKeyPressed(*it)) {
      it = consumed_primary_keys_.erase(it);
    } else {
      ++it;
    }
  }

  const bool alt_down = IsVirtualKeyPressed(VK_MENU);
  const bool ctrl_down = IsVirtualKeyPressed(VK_CONTROL);
  const bool shift_down = IsVirtualKeyPressed(VK_SHIFT);
  const bool meta_down =
      IsVirtualKeyPressed(VK_LWIN) || IsVirtualKeyPressed(VK_RWIN);

  for (const auto& [action, binding] : hotkey_bindings_) {
    if (!binding.core && !overlay_hotkeys_enabled_) {
      continue;
    }

    const bool is_pressed =
        IsBindingPressed(binding, alt_down, ctrl_down, shift_down, meta_down);
    bool& was_pressed = last_pressed_state_[action];

    if (is_pressed) {
      if (binding.repeat) {
        EmitHotkeyEvent(action, true);
      } else if (!was_pressed &&
                 consumed_primary_keys_.count(*binding.virtual_key) == 0) {
        consumed_primary_keys_.insert(*binding.virtual_key);
        EmitHotkeyEvent(action, true);
      }
    } else if (was_pressed) {
      EmitHotkeyEvent(action, false);
    }
    was_pressed = is_pressed;
  }
}

void FlutterWindow::EmitHotkeyEvent(const std::string& action, bool pressed) {
  if (!navigation_channel_) return;
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  payload[flutter::EncodableValue("pressed")] = flutter::EncodableValue(pressed);
  navigation_channel_->InvokeMethod(
      "onHotkeyEvent", std::make_unique<flutter::EncodableValue>(payload));
}

bool FlutterWindow::IsBindingPressed(const HotkeyBinding& binding,
                                     bool alt_down, bool ctrl_down,
                                     bool shift_down, bool meta_down) const {
  if (!binding.virtual_key.has_value()) {
    return false;
  }

  if (!IsVirtualKeyPressed(*binding.virtual_key)) {
    return false;
  }

  return alt_down == binding.requires_alt &&
         ctrl_down == binding.requires_ctrl &&
         shift_down == binding.requires_shift &&
         meta_down == binding.requires_meta;
}
