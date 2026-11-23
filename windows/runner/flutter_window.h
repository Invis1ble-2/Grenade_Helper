#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <optional>
#include <string>

#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool is_overlay = false);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct HotkeyBinding {
    std::optional<int> virtual_key;
    bool requires_alt = false;
    bool requires_ctrl = false;
    bool requires_shift = false;
    bool requires_meta = false;
    bool core = false;
    bool repeat = false;
  };

  void HandleHotkeyMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleOverlayWindowMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ClearHotkeyBindings();
  void UpdateHotkeyTimer();
  void StopHotkeyTimer();
  void PollHotkeys();
  void EmitHotkeyEvent(const std::string& action, bool pressed);
  bool IsBindingPressed(const HotkeyBinding& binding) const;

  flutter::DartProject project_;
  bool is_overlay_ = false;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      navigation_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      overlay_window_channel_;
  std::map<std::string, HotkeyBinding> hotkey_bindings_;
  std::map<std::string, bool> last_pressed_state_;
  bool overlay_hotkeys_enabled_ = false;
  bool hotkey_timer_active_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
