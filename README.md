Here’s a complete `README.md` for your Minikube AI Watchdog project. It covers the architecture, prerequisites, setup, Kubernetes deployment, Ollama/OpenAI configuration, SMTP email alerts, testing, troubleshooting, and security considerations.

Writing

# Minikube AI Watchdog

An AI-powered Kubernetes monitoring agent that detects unhealthy pods in a Minikube cluster, collects diagnostic evidence, generates troubleshooting recommendations using an LLM, and sends email alerts.

The watchdog continuously monitors configured Kubernetes namespaces and detects common pod issues such as `CrashLoopBackOff`, `ImagePullBackOff`, `OOMKilled`, repeated container restarts, and scheduling failures.

It sends an initial alert immediately after detecting an issue, then generates an AI-assisted diagnosis asynchronously and sends a follow-up email when available.

## Features

- **Automated pod monitoring:** Periodically scans configured Kubernetes namespaces.
- **Issue detection:** Identifies common container failures and pod health problems.
- **Diagnostic evidence collection:** Collects pod status, container state, recent logs, and Kubernetes events.
- **AI-powered diagnosis:** Uses Ollama with a local language model or OpenAI's API to recommend troubleshooting steps.
- **Email notifications:** Sends incident alerts and separate AI diagnosis reports through SMTP.
- **Persistent incident tracking:** Uses SQLite to track incidents and retry failed initial email notifications.
- **Duplicate alert suppression:** Avoids repeatedly emailing for the same detected incident.
- **Kubernetes-native deployment:** Runs as a Kubernetes Deployment with namespace-scoped RBAC.
- **Security-conscious configuration:** Runs the watchdog as a non-root user with a read-only root filesystem and dropped Linux capabilities.

> **Important:** The watchdog recommends remediation steps but does not automatically execute fixes against your cluster.

## Architecture

```
flowchart TD
    A[Minikube Cluster] --> B[AI Watchdog]
    B --> C[Scan Configured Namespaces]
    C --> D[Detect Pod Issues]
    D --> E[Collect Logs, Events and Status]
    E --> F[Persist Incident in SQLite]
    F --> G[Send Initial Email Alert]
    G --> H[Background Diagnosis]
    H --> I[Ollama or OpenAI]
    I --> J[Generate Troubleshooting Report]
    J --> K[Send Follow-up Email]

    F --> L[Persistent Volume]
    M[SMTP Server] --> G
    M --> K
```

### Components

| Component | Purpose |
| --- | --- |
| AI Watchdog | Python application that monitors pods and manages incidents |
| Kubernetes API | Provides pod status, container logs, and events |
| Ollama | Runs a local LLM for AI-assisted diagnosis |
| OpenAI API | Optional alternative LLM provider |
| SMTP server | Delivers initial alerts and diagnosis reports |
| SQLite | Stores incident state and pending email reports |
| PersistentVolumeClaim | Preserves Ollama models and incident state across pod restarts |

## Technology Stack

- Python 3.12
- Kubernetes Python client
- Minikube
- Docker
- Ollama and Qwen 2.5 3B (default local model)
- OpenAI API (optional)
- SQLite
- SMTP with STARTTLS
- Kubernetes Deployments, Services, Secrets, RBAC, and PersistentVolumeClaims

## Project Structure

```
minikube-ai-watchdog/
├── app/
│   ├── __init__.py
│   ├── main.py
│   └── main.py.bak
├── k8s/
│   ├── deployment.yaml
│   ├── namespace.yaml
│   ├── ollama.yaml
│   ├── rbac.yaml
│   ├── smtp-test.yaml
│   └── storage.yaml
├── Dockerfile
├── dockerignore
├── requirements.txt
└── README.md
```

`app/main.py` contains the monitoring loop, issue detection, evidence collection, AI diagnosis, and email notification logic.

`app/main.py.bak` is a backup file and is not required by the Docker build.

## Prerequisites

Install the following tools before proceeding:

- [Docker](<https://docs.docker.com/get-started/get-docker/>)
- [Minikube](<https://minikube.sigs.k8s.io/docs/start/>)
- [kubectl](<https://kubernetes.io/docs/tasks/tools/>)
- Git, if cloning the repository

For local AI inference, ensure your machine has sufficient memory and CPU resources. The included Ollama deployment requests 500 millicores of CPU and 2 GiB of memory, with a memory limit of 4 GiB, in addition to the resources required by Minikube and other workloads.

The model download also requires sufficient persistent storage and network connectivity.

## 1\. Start Minikube

Start a Minikube cluster with enough resources for the watchdog and local LLM.

```
minikube start --cpus=4 --memory=8192
```

Verify the cluster:

```
kubectl get nodes
kubectl cluster-info
```

Check that the current kubectl context points to your Minikube cluster:

```
kubectl config current-context
```

## 2\. Build the Watchdog Docker Image

From the project root:

```
docker build -t minikube-ai-watchdog:0.1.0 .
```

Make the image available inside Minikube.

If Minikube uses its own container runtime, load the image:

```
minikube image load minikube-ai-watchdog:0.1.0
```

Verify the image is available:

```
minikube image ls
```

The deployment uses `imagePullPolicy: IfNotPresent`, so the image should be loaded into the Minikube runtime before deploying the watchdog.

## 3\. Create SMTP and Optional OpenAI Secrets

The watchdog requires SMTP configuration to send alerts.

The expected Kubernetes Secret is named `watchdog-secrets` in the `ai-watchdog` namespace and contains the following keys:

| Key | Description |
| --- | --- |
| `smtp-host` | SMTP server hostname |
| `smtp-user` | SMTP authentication username |
| `smtp-password` | SMTP password or provider-specific app password |
| `email-from` | Sender email address |
| `email-to` | Recipient email address |
| `openai-api-key` | Optional OpenAI API key |

For Gmail, use `smtp.gmail.com` with port `587` and an app password when required by your account configuration. Do not use your regular Gmail account password.

Create a local `.env` file with the required values:

```
SMTP_HOST=smtp.gmail.com
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
EMAIL_FROM=your-email@gmail.com
EMAIL_TO=recipient@example.com

# Optional: required only when using the OpenAI provider
OPENAI_API_KEY=
```

Replace the example values with your own configuration.

**Never commit****`.env`****, SMTP passwords, or API keys to Git.** The repository's Docker ignore file should also exclude local secrets and development artifacts.

Create the namespace first:

```
kubectl apply -f k8s/namespace.yaml
```

Create the Kubernetes Secret from the local environment file:

```
kubectl create secret generic watchdog-secrets \
  --namespace ai-watchdog \
  --from-literal=smtp-host="$SMTP_HOST" \
  --from-literal=smtp-user="$SMTP_USER" \
  --from-literal=smtp-password="$SMTP_PASSWORD" \
  --from-literal=email-from="$EMAIL_FROM" \
  --from-literal=email-to="$EMAIL_TO"
```

The shell variables must be exported or loaded into the current shell first. For example, in a trusted local development environment:

```
set -a
source .env
set +a
```

If you intend to use OpenAI, create the optional key in the Secret:

```
kubectl create secret generic watchdog-secrets \
  --namespace ai-watchdog \
  --from-literal=smtp-host="$SMTP_HOST" \
  --from-literal=smtp-user="$SMTP_USER" \
  --from-literal=smtp-password="$SMTP_PASSWORD" \
  --from-literal=email-from="$EMAIL_FROM" \
  --from-literal=email-to="$EMAIL_TO" \
  --from-literal=openai-api-key="$OPENAI_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

If you do not use OpenAI, the `openai-api-key` key can be omitted because it is optional in the watchdog Deployment.

The commands above place credentials in Kubernetes Secrets, but Secrets are not automatically encrypted in every cluster configuration. Restrict access to them and avoid printing their contents in logs or committing rendered Secret manifests.

## 4\. Deploy Ollama

The default configuration uses Ollama running inside Kubernetes.

Apply its Deployment and Service:

```
kubectl apply -f k8s/ollama.yaml
```

Wait for the Ollama pod to become ready:

```
kubectl get pods -n ai-watchdog
kubectl rollout status deployment/ollama -n ai-watchdog
```

Download the configured model:

```
kubectl exec -n ai-watchdog deployment/ollama -- \
  ollama pull qwen2.5:3b
```

Verify the model is installed:

```
kubectl exec -n ai-watchdog deployment/ollama -- \
  ollama list
```

The model is stored under `/root/.ollama` in the Ollama container, backed by the `ollama-models` PersistentVolumeClaim.

The watchdog connects to Ollama through the Kubernetes Service:

```
http://ollama:11434
```

Because the watchdog and Ollama are in the same namespace, Kubernetes DNS resolves the Service name.

## 5\. Configure the LLM Provider

The deployment supports two diagnosis providers.

### Option A: Ollama (default)

The included configuration uses:

```
- name: LLM_PROVIDER
  value: "ollama"
- name: OLLAMA_URL
  value: "http://ollama:11434"
- name: OLLAMA_MODEL
  value: "qwen2.5:3b"
```

This runs inference locally within your Minikube environment. No OpenAI API key is required.

### Option B: OpenAI

Edit `k8s/deployment.yaml`:

```
- name: LLM_PROVIDER
  value: "openai"
- name: OPENAI_MODEL
  value: "gpt-4.1-mini"
```

Ensure the `watchdog-secrets` Secret includes `openai-api-key`.

The OpenAI Python client reads `OPENAI_API_KEY` from the environment. The included Deployment injects this environment variable from the Kubernetes Secret.

After changing the provider:

```
kubectl apply -f k8s/deployment.yaml
kubectl rollout status deployment/ai-watchdog -n ai-watchdog
```

When using OpenAI, diagnostic evidence—including recent logs and Kubernetes event messages—may be sent to the external API. Review your data-handling requirements before enabling this option.

## 6\. Deploy the Watchdog

Apply the remaining Kubernetes manifests:

```
kubectl apply -f k8s/storage.yaml
kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/deployment.yaml
```

The namespace and SMTP Secret must exist before deploying the watchdog. Ollama should also be deployed and have its model downloaded if you use the default provider.

Wait for the watchdog Deployment:

```
kubectl rollout status deployment/ai-watchdog -n ai-watchdog
```

Check the pods:

```
kubectl get pods -n ai-watchdog
```

Check the watchdog logs:

```
kubectl logs -n ai-watchdog deployment/ai-watchdog -f
```

Expected startup messages include:

```
Watching namespaces: default
LLM provider: ollama; poll interval: 30s
```

The watchdog is now monitoring the configured namespaces.

## Configuration Reference

The following environment variables control the watchdog.

| Variable | Default | Purpose |
| --- | --- | --- |
| `WATCH_NAMESPACES` | `default` | Comma-separated list of namespaces to monitor |
| `POLL_SECONDS` | `30` | Delay between monitoring scans; minimum 10 seconds |
| `LOG_TAIL_LINES` | `80` | Number of recent log lines to collect, bounded between 10 and 200 |
| `STATE_DB` | `/data/incidents.sqlite3` | SQLite database path |
| `LLM_PROVIDER` | `ollama` | Diagnosis provider: `ollama` or `openai` |
| `OLLAMA_URL` | `http://ollama:11434` | Ollama Service URL |
| `OLLAMA_MODEL` | `qwen2.5:3b` | Local Ollama model |
| `OPENAI_MODEL` | `gpt-4.1-mini` | OpenAI model |
| `SMTP_HOST` | Required | SMTP hostname |
| `SMTP_PORT` | `587` | SMTP port |
| `SMTP_USER` | Required | SMTP authentication username |
| `SMTP_PASSWORD` | Required | SMTP authentication password |
| `EMAIL_FROM` | Required | Sender address |
| `EMAIL_TO` | Required | Recipient address |
| `SMTP_STARTTLS` | `true` | Enables SMTP STARTTLS |

Environment variables for credentials are populated from Kubernetes Secrets in the provided Deployment.

To monitor multiple namespaces, update `WATCH_NAMESPACES`, for example:

```
- name: WATCH_NAMESPACES
  value: "default,staging"
```

You must also configure the appropriate Role and RoleBinding for each additional namespace. The included RBAC configuration grants access to `default` only.

## How Incident Detection Works

The watchdog checks pod and container status for the following conditions:

| Condition | Detection |
| --- | --- |
| `CrashLoopBackOff` | Container waiting reason |
| `ImagePullBackOff` | Container waiting reason |
| `ErrImagePull` | Container waiting reason |
| `CreateContainerConfigError` | Container waiting reason |
| `CreateContainerError` | Container waiting reason |
| `OOMKilled` | Container's terminated reason |
| High restart count | Container restart count of at least 3 |
| `PodFailed` | Pod phase is `Failed` |
| Scheduling failure | Pod is `Pending` and scheduling condition is false |

When an issue is detected, the watchdog creates an incident fingerprint based on the namespace, pod name, pod UID, and detected reason.

This helps distinguish different pod instances and incident types.

## Email Notification Workflow

For a new incident, the watchdog:

1. Collects pod status, container details, recent logs, and Kubernetes events.
2. Generates an incident report with relevant Kubernetes documentation links.
3. Saves the initial report in SQLite with a pending status.
4. Attempts to send the initial email alert.
5. Marks the incident as sent after successful delivery.
6. Starts a background thread to generate an AI diagnosis.
7. Sends a separate email containing the diagnosis and recommended remediation steps.

If sending the initial email fails, the watchdog retries the persisted report on a subsequent monitoring scan.

If the AI provider is unavailable, the report includes a fallback message and the collected diagnostic evidence remains available.

The asynchronous design prevents a slow LLM response from blocking the initial alert, although SMTP operations and evidence collection can still delay a monitoring scan.

## Testing the Watchdog

### 1\. Verify SMTP Configuration

A dedicated SMTP test pod is provided in `k8s/smtp-test.yaml`.

Create the test pod:

```
kubectl apply -f k8s/smtp-test.yaml
```

Inspect its output:

```
kubectl logs -n ai-watchdog smtp-test
```

On success, the output should contain:

```
SMTP_TEST_SUCCESS: test email sent
```

Check your inbox and spam folder for the test email.

The test pod is configured to use port 587 with STARTTLS. If you change the SMTP server or port, update the test manifest accordingly.

### 2\. Create a Test Workload

To verify detection, create a pod that repeatedly fails.

Save the following manifest as `test-crash-pod.yaml`:

```
apiVersion: v1
kind: Pod
metadata:
  name: watchdog-crash-test
  namespace: default
spec:
  restartPolicy: Always
  containers:
    - name: crash-container
      image: busybox:1.36
      command: ["/bin/sh", "-c"]
      args:
        - "echo 'Intentional watchdog test failure'; exit 1"
```

Apply the manifest:

```
kubectl apply -f test-crash-pod.yaml
```

Wait for the container to restart several times:

```
kubectl get pod watchdog-crash-test -n default -w
```

Inspect the pod:

```
kubectl describe pod watchdog-crash-test -n default
kubectl logs watchdog-crash-test -n default --previous
```

Once the restart count reaches the configured threshold or the container enters `CrashLoopBackOff`, the watchdog should detect the incident during its next scan.

Check the watchdog logs:

```
kubectl logs -n ai-watchdog deployment/ai-watchdog -f
```

Check your inbox for the initial alert, followed by a separate AI diagnosis email if the diagnosis and follow-up email succeed.

The first email should not wait for the LLM to finish.

### 3\. Clean Up the Test Workload

Delete the test pod when finished:

```
kubectl delete pod watchdog-crash-test -n default
```

Delete the SMTP test pod:

```
kubectl delete pod smtp-test -n ai-watchdog
```

## Troubleshooting

### Watchdog Pod Is Not Starting

Check pod status and events:

```
kubectl get pods -n ai-watchdog
kubectl describe pod -n ai-watchdog -l app=ai-watchdog
kubectl logs -n ai-watchdog deployment/ai-watchdog
```

Common causes include missing Secrets, invalid environment variables, image loading problems, and unavailable persistent volumes.

### Kubernetes API Access Denied

Check the RoleBinding and Role:

```
kubectl get role,rolebinding -n default
kubectl auth can-i list pods \
  --as=system:serviceaccount:ai-watchdog:ai-watchdog \
  -n default
```

Check log access:

```
kubectl auth can-i get pods/log \
  --as=system:serviceaccount:ai-watchdog:ai-watchdog \
  -n default
```

The watchdog requires permission to list and inspect pods, read pod logs, and list Kubernetes events in each monitored namespace.

### Ollama Is Unavailable

Check the Ollama Deployment and Service:

```
kubectl get pods,svc -n ai-watchdog
kubectl logs -n ai-watchdog deployment/ollama
```

Test the API from inside the Ollama pod:

```
kubectl exec -n ai-watchdog deployment/ollama -- \
  ollama list
```

If the model is missing, pull it again:

```
kubectl exec -n ai-watchdog deployment/ollama -- \
  ollama pull qwen2.5:3b
```

Verify that `OLLAMA_URL` points to the correct Service and that the model is compatible with the available resources.

### AI Diagnosis Is Slow

The default request timeout is 180 seconds.

Local inference performance depends on available CPU, memory, and the model size. Review the Ollama pod's resource usage and logs before increasing timeouts.

The initial alert is designed to be sent before AI diagnosis completes.

### Email Alerts Are Not Received

Check the watchdog logs:

```
kubectl logs -n ai-watchdog deployment/ai-watchdog --tail=200
```

Check the SMTP test pod output and verify:

- SMTP hostname and port.
- SMTP username and password.
- Sender and recipient addresses.
- STARTTLS requirements.
- SMTP provider restrictions and network connectivity.
- Gmail app password configuration, if applicable.

The initial email and the asynchronous diagnosis email are separate operations. A successful initial alert does not guarantee that the diagnosis email will be delivered.

### Persistent Volume Issues

Check the PersistentVolumeClaims:

```
kubectl get pvc -n ai-watchdog
kubectl describe pvc ai-watchdog-state -n ai-watchdog
kubectl describe pvc ollama-models -n ai-watchdog
```

The watchdog uses `ai-watchdog-state` for SQLite incident data. Ollama uses `ollama-models` for model storage.

Avoid deleting PVCs if you need to preserve incident history or downloaded models.

## Security Considerations

- The watchdog runs as UID/GID `10001`, with privilege escalation disabled and all Linux capabilities dropped.
- Its root filesystem is read-only; writable incident data is mounted at `/data`.
- Kubernetes permissions are restricted to the explicitly configured namespaces.
- SMTP credentials and API keys are supplied through Kubernetes Secrets.
- Diagnostic logs and events are treated as untrusted input by the AI prompt.
- The application recommends remediation only and does not execute commands against the cluster.
- Collected logs may contain sensitive information. Review log retention and data-handling policies before sending evidence to an external LLM.
- Avoid exposing the Ollama Service publicly unless you have an explicit security requirement and appropriate access controls.

For production deployments, consider enabling Kubernetes Secret encryption at rest, applying network policies, pinning container images to verified versions, and adding resource limits and monitoring for the Ollama workload.

## Limitations

- Monitoring is based on periodic polling rather than Kubernetes watch streams.
- Detection is limited to the conditions implemented in `detect_issue()`.
- Only the namespaces configured in `WATCH_NAMESPACES` are monitored.
- The current SQLite schema records incident state and suppresses duplicate initial alerts; it is not a full incident management platform.
- The initial email retry workflow does not guarantee exactly-once delivery if SMTP succeeds but the application fails before recording the sent status.
- AI diagnoses are suggestions, not guaranteed root-cause determinations.
- The asynchronous diagnosis uses a background thread and is not durably queued. If the watchdog process exits before the thread finishes, the follow-up diagnosis may be lost.
- The included Ollama deployment uses a single replica and may require resource tuning for larger models or heavier workloads.

## Future Enhancements

Potential improvements include:

- Kubernetes watch-based event monitoring.
- A durable job queue for AI diagnosis.
- Incident history dashboards and metrics.
- Slack, Microsoft Teams, and webhook notifications.
- Configurable severity levels and alert routing.
- Support for more Kubernetes failure conditions.
- Automated diagnosis evaluation and structured output validation.
- Integration with Prometheus and Grafana.
- Optional approval-based remediation workflows.

## License

No license has been specified yet. Add a `LICENSE` file before distributing or publishing the project if you intend to grant others permission to use, modify, or redistribute it.

## Acknowledgements

- [Kubernetes Documentation](<https://kubernetes.io/docs/>)
- [Minikube](<https://minikube.sigs.k8s.io/docs/>)
- [Ollama](<https://ollama.com/>)
- [OpenAI API](<https://platform.openai.com/docs/>)

## Important checks before running it

I noticed a few details in your current manifests worth addressing before treating this as a production-ready project:

1. Ollama model initialization: The Ollama Deployment does not automatically pull `qwen2.5:3b`. Run the `ollama pull` command after the pod starts.
2. Secret creation: Create the `ai-watchdog` namespace and `watchdog-secrets` Secret before deploying the watchdog. The OpenAI key is optional for Ollama but required when selecting OpenAI.
3. RBAC: The current Role and RoleBinding grant access to the `default` namespace only. Every additional monitored namespace needs its own appropriate permissions.
4. Background diagnosis: Your current `main.py` sends the initial alert before launching diagnosis, which is good for responsiveness. However, the follow-up runs in a daemon thread and may be interrupted if the process terminates.
5. Persistent storage: Keep both PVCs if you want to retain incident records and avoid repeatedly downloading the Ollama model.

Developed & Maintained By - Pranav Jambare
