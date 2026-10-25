#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kRuntimeChannelName[] = "plug_agente/runtime";
constexpr char kDeepLinkMethodName[] = "deliverDeepLink";
constexpr char kShowWindowMethodName[] = "showWindow";
constexpr ULONG_PTR kRuntimeDeepLinkMessageId = 0x706c7567;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool show_on_first_frame)
    : project_(project), show_on_first_frame_(show_on_first_frame) {}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  runtime_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kRuntimeChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  runtime_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == kShowWindowMethodName) {
          if (this->Show()) {
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Error("show_window_failed",
                          "Failed to show the native window.");
          }
          return;
        }

        result->NotImplemented();
      });

  installation_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "plug_agente/installation", &flutter::StandardMethodCodec::GetInstance());
  installation_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    try {
      if (call.method_name() == "enable") { result->Success(flutter::EncodableValue(installation_.start())); return; }
      if (call.method_name() == "poll") { result->Success(flutter::EncodableValue(installation_.poll())); return; }
      if (call.method_name() == "cancelled") { result->Success(flutter::EncodableValue(installation_.cancelled())); return; }
      if (call.method_name() == "report") {
        if (!call.arguments() || !std::holds_alternative<std::string>(*call.arguments())) throw std::runtime_error("invalid_report");
        installation_.report(std::get<std::string>(*call.arguments())); result->Success(); return;
      }
      result->NotImplemented();
    } catch (const std::exception&) { result->Error("installation_coordination_failed", "Installation coordination failed"); }
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (show_on_first_frame_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  installation_channel_.reset();
  runtime_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

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
    case WM_COPYDATA: {
      auto* copy_data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (copy_data != nullptr &&
          copy_data->dwData == kRuntimeDeepLinkMessageId &&
          copy_data->lpData != nullptr && copy_data->cbData > 0) {
        const auto payload_length =
            static_cast<size_t>(copy_data->cbData) - 1;
        DeliverDeepLink(std::string(
            static_cast<const char*>(copy_data->lpData), payload_length));
        return 0;
      }
      break;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::DeliverDeepLink(const std::string& deep_link) {
  if (!runtime_channel_) {
    return;
  }

  runtime_channel_->InvokeMethod(
      kDeepLinkMethodName,
      std::make_unique<flutter::EncodableValue>(deep_link));
}
