import argparse
import random
import signal
import time
from collections import Counter
from datetime import datetime

import requests

COUNTRIES = [
    "United States", "Canada", "Mexico", "Brazil", "United Kingdom", "France",
    "Germany", "Italy", "Spain", "India", "China", "Japan", "South Korea",
    "Australia", "Nigeria", "Egypt", "South Africa", "Argentina",
    "North Korea", "Iran", "Cuba", "Myanmar", "Iraq", "Libya", "Sudan",
    "Zimbabwe", "Syria",
]
GENDERS = ["Male", "Female"]
AGES = ["0-16", "17-25", "26-35", "36-45", "46-55", "56-65", "66-75", "76+"]
INCOMES = ["0-10k", "10k-20k", "20k-40k", "40k-60k", "60k-100k",
           "100k-150k", "150k-250k", "250k+"]


def now():
    return datetime.now().strftime("%H:%M:%S.%f")[:-3]


def random_ip():
    return ".".join(str(random.randint(1, 254)) for _ in range(4))


def build_headers():
    return {
        "X-country": random.choice(COUNTRIES),
        "X-client-IP": random_ip(),
        "X-gender": random.choice(GENDERS),
        "X-age": random.choice(AGES),
        "X-income": random.choice(INCOMES),
        "X-time": str(int(time.time())),
        "Connection": "close",
    }


def main():
    parser = argparse.ArgumentParser(description="CS528 HW8 load balancer client")
    parser.add_argument("host", help="load balancer IP, optionally host:port")
    parser.add_argument("-n", "--count", type=int, default=0,
                        help="number of requests (0 = run until Ctrl+C)")
    parser.add_argument("-i", "--interval", type=float, default=1.0,
                        help="seconds between requests")
    parser.add_argument("-t", "--timeout", type=float, default=2.0,
                        help="per-request timeout in seconds")
    parser.add_argument("--num-files", type=int, default=12000,
                        help="files are named 0..num-files-1")
    parser.add_argument("--prefix", default="files/",
                        help="path prefix of the files in the bucket")
    args = parser.parse_args()

    zones = Counter()
    statuses = Counter()
    errors = []
    sent = 0
    stop = False

    def handle_sigint(signum, frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, handle_sigint)

    print(f"{'time':12}  {'#':>5}  {'status':8}  zone / error", flush=True)
    while not stop and (args.count == 0 or sent < args.count):
        start = time.monotonic()
        sent += 1
        url = f"http://{args.host}/{args.prefix}{random.randrange(args.num_files)}.html"
        ts = now()
        try:
            r = requests.get(url, headers=build_headers(), timeout=args.timeout)
            zone = r.headers.get("X-Zone", "no-zone-header")
            zones[zone] += 1
            statuses[r.status_code] += 1
            print(f"{ts:12}  {sent:5}  {r.status_code:<8}  {zone}", flush=True)
        except requests.exceptions.RequestException as e:
            kind = "TIMEOUT" if isinstance(e, requests.exceptions.Timeout) else "ERROR"
            errors.append(ts)
            print(f"{ts:12}  {sent:5}  {kind:8}  {type(e).__name__}", flush=True)
        delay = args.interval - (time.monotonic() - start)
        while delay > 0 and not stop:
            time.sleep(min(delay, 0.1))
            delay -= 0.1

    answered = sum(zones.values())
    print("\n===== Summary =====")
    print(f"Requests sent: {sent}")
    print(f"Answered:      {answered}")
    print(f"Errors:        {len(errors)}")
    if statuses:
        print("Status codes:  " + ", ".join(f"{k}: {v}" for k, v in sorted(statuses.items())))
    print("Requests per zone:")
    for zone, n in sorted(zones.items()):
        print(f"  {zone}: {n} ({100 * n / answered:.1f}%)")
    if errors:
        print(f"First error:   {errors[0]}")
        print(f"Last error:    {errors[-1]}")


if __name__ == "__main__":
    main()
