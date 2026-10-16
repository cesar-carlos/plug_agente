#include "win_security.h"
#include <chrono>
#include <future>
#include <iostream>
#include <thread>

using namespace plug::updater;
namespace {
void require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}
struct PipePair {
  Handle server;
  std::unique_ptr<Handle> client;
  PipePair() : server(create()) {
    client = std::make_unique<Handle>(CreateFileW(name().c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
        OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr));
    require(server.valid() && client->valid(), "pipe_fixture_unavailable");
    OVERLAPPED connection{}; Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)); connection.hEvent = event.get();
    const BOOL connected = ConnectNamedPipe(server.get(), &connection);
    require(connected || GetLastError() == ERROR_PIPE_CONNECTED, "pipe_fixture_not_connected");
  }
  static std::wstring name() {
    return L"\\\\.\\pipe\\PlugAgentePipeTest-" + std::to_wstring(GetCurrentProcessId());
  }
  static HANDLE create() {
    return CreateNamedPipeW(name().c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 65536, 65536, 0, nullptr);
  }
};
void fragmented_read() {
  PipePair pipes;
  auto writer = std::async(std::launch::async, [&] {
    for (uint8_t byte : {1, 2, 3, 4}) {
      require(pipe_transfer(pipes.client->get(), &byte, 1, true, 1000), "fragment_write_failed");
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  });
  uint8_t bytes[4]{};
  require(pipe_transfer(pipes.server.get(), bytes, 4, false, 1000), "fragmented_read_failed");
  writer.get();
  require(bytes[0] == 1 && bytes[3] == 4, "fragmented_bytes_changed");
}
void delayed_reply_reader(bool receipt) {
  PipePair pipes;
  auto reply = std::async(std::launch::async, [&] {
    const bool sent = pipe_reply(pipes.server.get(), R"({"ok":true,"status":{"state":"preparing"}})", 2000);
    DisconnectNamedPipe(pipes.server.get());
    return sent;
  });
  // Force the server to finish buffering before the client begins reading.
  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  DWORD length = 0;
  require(pipe_transfer(pipes.client->get(), &length, sizeof(length), false, 1000), "reply_header_lost");
  require(length > 0 && length < 256, "reply_size_invalid");
  std::string bytes(length, '\0');
  require(pipe_transfer(pipes.client->get(), bytes.data(), length, false, 1000), "reply_body_lost");
  require(parse_json(bytes).at("ok") == true, "reply_corrupted");
  if (receipt) {
    uint8_t received = 1;
    require(pipe_transfer(pipes.client->get(), &received, 1, true, 1000), "receipt_failed");
  } else {
    pipes.client.reset();
  }
  require(reply.wait_for(std::chrono::seconds(1)) == std::future_status::ready && reply.get(), "reply_completion_unbounded");
}
void unresponsive_reader_is_bounded() {
  PipePair pipes;
  auto reply = std::async(std::launch::async, [&] { return pipe_reply(pipes.server.get(), "{}", 100); });
  require(reply.wait_for(std::chrono::seconds(2)) == std::future_status::ready, "unresponsive_peer_blocks_service");
  require(reply.get(), "buffered_reply_failed");
}
void fragmented_deadline_is_not_reset() {
  PipePair pipes;
  auto writer = std::async(std::launch::async, [&] {
    uint8_t byte = 1;
    for (int index = 0; index < 20; ++index) {
      if (!pipe_transfer(pipes.client->get(), &byte, 1, true, 1000)) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
  });
  uint8_t bytes[20]{};
  require(!pipe_transfer(pipes.server.get(), bytes, sizeof(bytes), false, 100), "partial_reads_reset_deadline");
  writer.get();
}
}
int main() {
  try {
    fragmented_read();
    delayed_reply_reader(true);
    delayed_reply_reader(false);
    unresponsive_reader_is_bounded();
    fragmented_deadline_is_not_reset();
    std::cout << "Five real Windows pipe cases passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; return 1;
  }
}
