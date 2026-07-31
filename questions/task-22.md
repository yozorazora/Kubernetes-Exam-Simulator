# Task 22 — Job and CronJob
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Complete both parts in namespace `task22`:

---

**Part A — Create a Job:**

Create a Job named `task22-job` in namespace `task22` with:
- Image: `busybox:1.36`
- Command: `sh -c "echo 'Job completed'; sleep 2"`
- `completions`: `3`    ← must run to completion 3 times total
- `parallelism`: `2`    ← run up to 2 pods at the same time

The Job must complete all 3 runs successfully.

---

**Part B — Create a CronJob:**

Create a CronJob named `task22-cronjob` in namespace `task22` with:
- Image: `busybox:1.36`
- Command: `sh -c "date; echo 'Scheduled task ran'"`
- Schedule: `*/1 * * * *`   ← every 1 minute
- `successfulJobsHistoryLimit`: `3`

---

## Key Concepts

```
┌─────────────────────────────────────────────────────────────────────┐
│  Job                                │  CronJob                      │
│  ──────────────────────────────     │  ──────────────────────────   │
│  • Runs pod(s) to completion        │  • Creates Jobs on a schedule │
│  • completions: total runs needed   │  • Uses cron syntax           │
│  • parallelism: concurrent pods     │  • schedule: "*/1 * * * *"   │
│  • backoffLimit: retry on failure   │  • jobTemplate → Job spec     │
└─────────────────────────────────────────────────────────────────────┘

Cron syntax:  ┌─── minute (0-59)
              │  ┌── hour (0-23)
              │  │  ┌─ day of month (1-31)
              │  │  │  ┌ month (1-12)
              │  │  │  │  ┌ day of week (0-7, 0=Sun)
              │  │  │  │  │
             */1  *  *  *  *   ← every minute

Common schedules:
  */5 * * * *    every 5 minutes
  0 * * * *      every hour
  0 0 * * *      every day at midnight
  0 0 * * 1      every Monday at midnight
```

**Job lifecycle:**
```
Job created → pods run (up to parallelism) → each finishes → 
next pod starts → until completions reached → Job STATUS: Complete
```

**Checking Job status:**
```bash
kubectl -n task22 get job task22-job
# COMPLETIONS column shows: 3/3 when done

kubectl -n task22 describe job task22-job
# Look for: Pods Statuses: 0 Active / 3 Succeeded / 0 Failed
```

---

## Hint

<details>
<summary>Click to expand</summary>

**Job template (imperative — no built-in flags for completions/parallelism):**
```bash
# Generate YAML then edit
kubectl create job task22-job --image=busybox:1.36 \
  --dry-run=client -o yaml -- sh -c "echo 'Job completed'; sleep 2" > /tmp/job.yaml
# Then add completions: 3 and parallelism: 2 under spec:
kubectl apply -f /tmp/job.yaml -n task22
```

**CronJob imperative:**
```bash
kubectl create cronjob task22-cronjob \
  --image=busybox:1.36 \
  --schedule="*/1 * * * *" \
  -n task22 \
  -- sh -c "date; echo 'Scheduled task ran'"
# Then patch successfulJobsHistoryLimit:
kubectl -n task22 patch cronjob task22-cronjob \
  -p '{"spec":{"successfulJobsHistoryLimit":3}}'
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# Create namespace
kubectl create namespace task22 --dry-run=client -o yaml | kubectl apply -f -

# ── Part A: Job ─────────────────────────────────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: task22-job
  namespace: task22
spec:
  completions: 3
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.36
        command:
        - sh
        - -c
        - "echo 'Job completed'; sleep 2"
EOF

# Watch it progress
kubectl -n task22 get job task22-job -w
# Wait until COMPLETIONS shows 3/3

# See the pods that ran
kubectl -n task22 get pods --selector=job-name=task22-job

# ── Part B: CronJob ──────────────────────────────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: task22-cronjob
  namespace: task22
spec:
  schedule: "*/1 * * * *"
  successfulJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: scheduler
            image: busybox:1.36
            command:
            - sh
            - -c
            - "date; echo 'Scheduled task ran'"
EOF

# Verify
kubectl -n task22 get cronjob task22-cronjob
# Wait ~1 minute, then check jobs spawned by the CronJob:
kubectl -n task22 get jobs
```
