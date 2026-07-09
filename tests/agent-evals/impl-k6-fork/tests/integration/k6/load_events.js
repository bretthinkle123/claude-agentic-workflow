// k6 ingest load — POST /v1/events at a constant arrival rate across distributed keys.
// SHARED HARNESS: scenario-specific behavior comes in via environment (__ENV.*), not by
// copying this file. See test_perf_k6_load.py for the fixture that drives it.
import http from "k6/http";
import { check } from "k6";
import { Trend } from "k6/metrics";

const latency = new Trend("ingest_latency", true);

const BASE_URL = __ENV.BASE_URL || "http://host.docker.internal:8000";
const API_KEYS = (__ENV.API_KEYS || "").split(",").filter(Boolean);
const CUSTOMERS = parseInt(__ENV.CUSTOMER_BUCKETS || "50", 10);
const RATE = parseInt(__ENV.TARGET_RPS || "500", 10);
const DURATION = __ENV.MEASURE_DURATION || "15s";

export const options = {
  scenarios: {
    ingest: {
      executor: "constant-arrival-rate",
      rate: RATE,
      timeUnit: "1s",
      duration: DURATION,
      preAllocatedVUs: 100,
      maxVUs: 400,
    },
  },
};

function pick(arr, i) {
  return arr[i % arr.length];
}

export default function () {
  const i = Math.floor(Math.random() * 1_000_000);
  const key = pick(API_KEYS, i);
  const customer = `cust-${i % CUSTOMERS}`;
  const payload = JSON.stringify({
    customer_id: customer,
    metric: __ENV.METRIC || "api_calls",
    quantity: 1,
    idempotency_key: `k6-${__VU}-${__ITER}-${i}`,
  });
  const res = http.post(`${BASE_URL}/v1/events`, payload, {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
  });
  latency.add(res.timings.duration);
  check(res, { "status is 2xx": (r) => r.status >= 200 && r.status < 300 });
}
