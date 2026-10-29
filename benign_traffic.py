import concurrent.futures
import csv
import random
import signal
import sys
import time
import urllib.error
import urllib.request
TARGET_HOST = "192.168.20.10"
TARGET_PORT = 80
CONCURRENT_USERS = 8
QOS_LOG = "benign_qos_log.csv"
ENDPOINTS = [
    "/",
    "/index.html",
    "/about.html",
    "/api/data.json",
    "/api/data.json?filter=active",
    "/index.html?session=guest",
]
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/119.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1."
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
]
stop_requested = False
def signal_handler(sig, frame):
    global stop_requested
    print("\n[*] Stopping benign traffic generator cleanly...")
    stop_requested = True
signal.signal(signal.SIGINT, signal_handler)
# Initialize QoS CSV log
with open(QOS_LOG, mode="w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(
        ["timestamp_utc", "endpoint", "status_code", "latency_ms", "result"]
    )
def log_qos(ts, endpoint, code, latency, result):
    with open(QOS_LOG, mode="a", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([ts, endpoint, code, f"{latency:.2f}", result])
def simulate_user(user_id):
    while not stop_requested:
        endpoint = random.choice(ENDPOINTS)
        url = f"http://{TARGET_HOST}:{TARGET_PORT}{endpoint}"
        ua = random.choice(USER_AGENTS)
        ts = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime())
        start_time = time.time()
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": ua,
                "Accept": "text/html,application/json,*/*",
                "Connection": "keep-alive",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=4) as response:
                latency = (time.time() - start_time) * 1000
                log_qos(ts, endpoint, response.status, latency, "SUCCESS")
                print(
                    f"[{ts}] User-{user_id} GET {endpoint:<26} -> {response.status} ({latency:.1f} ms)"
                )
        except urllib.error.HTTPError as e:
            latency = (time.time() - start_time) * 1000
            log_qos(ts, endpoint, e.code, latency, "HTTP_ERROR")
            print(f"[{ts}] User-{user_id} GET {endpoint:<26} -> HTTP {e.code}")
        except urllib.error.URLError as e:
            latency = (time.time() - start_time) * 1000
            log_qos(ts, endpoint, 0, latency, "TIMEOUT_OR_DROPPED")
            print(
                f"[{ts}] User-{user_id} GET {endpoint:<26} -> FAILED ({e.reason})"
            )
        except Exception as e:
            latency = (time.time() - start_time) * 1000
            log_qos(ts, endpoint, 0, latency, "EXCEPTION")
            print(f"[{ts}] User-{user_id} Error: {e}")
        # Human think-time jitter (0.3s to 1.8s)
        time.sleep(random.uniform(0.3, 1.8))
print(
    f"[*] Spawning {CONCURRENT_USERS} simulated benign users targeting {TARGET_HOST}..."
)
with concurrent.futures.ThreadPoolExecutor(
    max_workers=CONCURRENT_USERS
) as executor:
    futures = [
        executor.submit(simulate_user, i + 1) for i in range(CONCURRENT_USERS)
    ]
    while not stop_requested:
        time.sleep(1)
print(f"[*] Benign QoS log saved to {QOS_LOG}.")