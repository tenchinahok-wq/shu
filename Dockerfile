FROM ubuntu:22.04

# 1. Cài đặt các công cụ cơ bản
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps masscan libpcap-dev coreutils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt Go 1.25.0 (Bản mới nhất)
RUN wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz && \
    rm go1.25.0.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin
ENV GOROOT=/usr/local/go

# 3. Cài đặt thư viện Python
RUN pip3 install pyTelegramBotAPI flask psutil --break-system-packages || pip3 install pyTelegramBotAPI flask psutil

# 4. Tạo script Bot bằng cách giải mã Base64 (Để tránh lỗi dấu nháy khi build)
RUN echo "aW1wb3J0IHRlbGVib3QKaW1wb3J0IG9zLCBzdWJwcm9jZXNzLCB0aW1lLCBwc3V0aWwsIHRocmVhZGluZwpmcm9tIGZsYXNrIGltcG9ydCBGbGFzawoKVE9LRU4gPSBvcy5nZXRlbnYoIlRFTEVHUkFNX1RPS0VOIikKQUstandardERNX0lEID0gb3MuZ2V0ZW52KCJBRE1JTl9JRCIpCmJvdCA9IHRlbGVib3QuVGVsZUJvdChUT0tFTiwgdGhyZWFkZWQ9RmFsc2UpCmFwcCA9IEZsYXNrKF9fbmFtZV9fKQoKc3RhdGUgPSB7ImN3ZCI6IG9zLmdldGN3ZCgpfQoKQGFwcC5yb3V0ZS("/")CmRlZiBoZWFsdGgoKTogcmV0dXJuICJMaXZlIFRlcm1pbmFsIE9ubGluZSIsIDIwMAoKZGVmIGdldF9zdGF0cygpOgogICAgcmV0dXJuIHBzdXRpbC5jcHVfcGVyY2VudChpbnRlcnZhbD1Ob25lKSwgcHN1dGlsLnZpcnR1YWxfbWVtb3J5KCkucGVyY2VudCwgc3VicHJvY2Vzcy5nZXRvdXRwdXQoInVwdGltZSAtcCIpCgpkZWYgZGFzaGJvYXJkX2xvb3AoY2hhdF9pZCwgbWVzc2FnZV9pZCk6CiAgICB3aGlsZSBUcnVlOgogICAgICAgIHRyeToKICAgICAgICAgICAgY3B1LCByYW0sIHVwdGltZSA9IGdldF9zdGF0cygpCiAgICAgICAgICAgIHRleHQgPSAoZCI🖥️ **LIVE MONITOR**\n━━━━━━━━━━━━━━━━━━━━\n"CiAgICAgICAgICAgICAgICAgICBmZCJ📂 **Dir:** `{state['cwd']}`\n"CiAgICAgICAgICAgICAgICAgICBmZCJ📟 **CPU:** `{cpu}%` | 🧠 **RAM:** `{ram}%`\n"CiAgICAgICAgICAgICAgICAgICBmZCJ⏱️ **{uptime}**\n━━━━━━━━━━━━━━━━━━━━\n"CiAgICAgICAgICAgICAgICAgICBmZCJ🕒 Update: `{time.strftime('%H:%M:%S')}`\")\nICAgICAgICAgICAgYm90LmVkaXRfbWVzc2FnZV90ZXh0KHRleHQsIGNoYXRfaWQsIG1lc3NhZ2VfaWQsIHBhcnNlX21vZGU9Ik1hcmtkb3duIikKICAgICAgICBleGNlcHQ6IHBhc3MKICAgICAgICB0aW1lLnNsZWVwKDE1KQoKQGJvdC5tZXNzYWdlX2hhbmRsZXIoY29tbWFuZHM9WyJzdGFydCJdKQpkZWYgc3RhcnQobWVzc2FnZSk6CiAgICBpZiBzdHIobWVzc2FnZS5jaGF0LmlkKSA9PSBBRE1JTl9JRDoKICAgICAgICBzZW50ID0gYm90LnNlbmRfbWVzc2FnZShtZXNzYWdlLmNoYXRfaWQsICL📊IMSQYW5nIGto4bufaSB04bqhby4uLiIpCiAgICAgICAgdGhyZWFkaW5nLlRocmVhZCh0YXJnZXQ9ZGFzaGJvYXJkX2xvb3AsIGFyZ3M9KG1lc3NhZ2UuY2hhdFmlZCwgc2VudC5tZXNzYWdlX2lkKSwgZGFlbW9uPVRydWUpLnN0YXJ0KCkKCkBibm90Lm1lc3NhZ2VfaFhbmRsZXIoZnVuYz1sYW1iZGEgbTogc3RyKG0uY2hhdC5pZCkgPT0gQURNSU5fSUQpCmRlZiBleGVjX2xpdmUobWVzc2FnZSk6CiAgICBjbWQgPSBtZXNzYWdlLnRleHQuc3RyaXAoKQogICAgdHJ5OiBib3QuZGVsZXRlX21lc3NhZ2UobWVzc2FnZS5jaGF0LmlkLCBtZXNzYWdlLm1lc3NhZ2VfaWQpCiAgICBleGNlcHQ6IHBhc3MKCiAgICBpZiBjbWQuc3RhcnRzd2l0aCgiY2QgIik6CiAgICAgICAgcGF0aCA9IG9zLnBhdGguYWJzcGF0aChvcy5wYXRoLmpvaW4oc3RhdGVbImN3ZCJdLCBjbWRbMzp9LnN0cmlwKCkpKQogICAgICAgIGlmIG9zLnBhdGguaXNkaXIocGF0aCk6IHN0YXRlWyJjd2QiXSA9IHBhdGgKICAgICAgICByZXR1cm4KCiAgICBzdGF0dXNfbXNnID0gYm90LnNlbmRfbWVzc2FnZShtZXNzYWdlLmNoYXRfaWQsIGZkI🚀 **Exec:** `{cmd}`\n`────────────────────`\n📡 *Đang kết nối...*\",IHBhcnNlX21vZGU9Ik1hcmtkb3duIikKCiAgICBkZWYgcnVuKCk6CiAgICAgICAgZnVsbF9vdXQgPSAiIgogICAgICAgIGxhc3RfdXAgPSAwCiAgICAgICAgdHJ5OgogICAgICAgICAgICBwID0gc3VicHJvY2Vzcy5QZGVwZW4oY21kLCBzaGVsbD1UcnVlLCBjd2Q9c3RhdGVbImN3ZCJdLCBzdGRvdXQ9c3VicHJvY2Vzcy5QSVBFLCBzdGRlcnI9c3VicHJvY2Vzcy5TVERPVVQsIHRleHQ9VHJ1ZSwgYnVmc2l6ZT0xKQogICAgICAgICAgICBmb3IgbGluZSBpbiBpdGVyKHAuc3Rkb3V0LnJlYWRsaW5lLCAiIik6CiAgICAgICAgICAgICAgICBmdWxsX291dCArPSBsaW5lCiAgICAgICAgICAgICAgICBpZiB0aW1lLnRpbWUoKSAtIGxhc3RfdXAgPiAxLjU6CiAgICAgICAgICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgICAgICAgICBib3QuZWRpdF9tZXNzYWdlX3RleHQoZmQi⚡ **Running:** `{cmd}`\n`────────────────────`\n
