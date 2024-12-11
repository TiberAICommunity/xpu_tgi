# Load Balancing a Model Across 8 XPUs with Traefik

This guide demonstrates how to deploy the `Phi3-mini` model across 8 Intel Max series GPUs (XPUs) and configure load balancing with Traefik. 

---

## Step 1: Deploy the Model to 8 XPUs

To deploy the model to all 8 GPUs sequentially, use the following bash command:

```bash
for i in {1..8}; do ./add_model.sh Phi-3-mini-128k; done
```

- **`add_model.sh`**: Assumes you have cloned this repo and have setup at least one model or the base services (network, auth and proxy).
- This command ensures all 8 instances (or 7 if you are already running 1 instance) are deployed one after another, not in parallel.

---

## Step 2: Gather Container Names

After deployment, extract the names of the running containers:

```bash
docker ps --filter "ancestor=ghcr.io/huggingface/text-generation-inference:2.4.0-intel-xpu" --format '{{.Names}}'
```

This will output the container names. Example:

```
tgi_phi-3-mini-128k-tgi_gpu7_dafbdb
tgi_phi-3-mini-128k-tgi_gpu6_520bff
tgi_phi-3-mini-128k-tgi_gpu5_5dd8a6
tgi_phi-3-mini-128k-tgi_gpu4_8ad771
tgi_phi-3-mini-128k-tgi_gpu3_55998e
tgi_phi-3-mini-128k-tgi_gpu2_fe21bc
tgi_phi-3-mini-128k-tgi_gpu1_8195ab
tgi_phi-3-mini-128k-tgi_gpu0_230bb7
```

---

## Step 3: Update Traefik Dynamic Configuration

Use the following one-liner to dynamically update the `traefik/dynamic.yml` file with the new container names:

```bash
docker ps --filter "ancestor=ghcr.io/huggingface/text-generation-inference:2.4.0-intel-xpu" --format '{{.Names}}' | awk 'BEGIN {print "http:\n  middlewares:\n    auth-forward:\n      forwardAuth:\n        address: \"http://tgi_auth:3000/validate\"\n        authResponseHeaders:\n          - \"X-Auth-Status\"\n\n    stripprefix:\n      stripPrefix:\n        prefixes:\n          - \"/phi3\"\n\n  services:\n    phi3-service:\n      loadBalancer:\n        servers:"} {print "          - url: \"http://" $1 ":80\""} END {print "        sticky:\n          cookie:\n            name: lb_phi3\n            secure: true\n\n  routers:\n    phi3-router:\n      rule: \"PathPrefix(`/phi3/generate`)\"\n      service: phi3-service\n      middlewares:\n        - auth-forward\n        - stripprefix"}' > traefik/dynamic.yml
```
> Note: You should be inside the parent repo (the traefik config is in ./traefik/dynamic.yml)
---

## Step 4: Verify and Reload Traefik

1. **Verify Dynamic Configuration**
   - Confirm the new `traefik/dynamic.yml` file has the updated container names.
   - Example of `servers` in the updated file:
     ```yaml
     servers:
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu0_230bb7:80"
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu1_8195ab:80"
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu2_fe21bc:80"
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu3_55998e:80"
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu4_8ad771:80"
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu5_5dd8a6:80"
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu6_520bff:80"
       - url: "http://tgi_phi-3-mini-128k-tgi_gpu7_dafbdb:80"
     ```

2. **Reload Traefik**
   - If using dynamic configuration, Traefik should automatically reload changes.
   - If necessary, manually restart Traefik:
     ```bash
     docker restart $(docker ps --filter "ancestor=traefik:v3.2.1" --format '{{.ID}}')
     ```

---

## Testing the Load Balancer

Send a test request to verify that the traffic is routed correctly across all GPUs:

```bash
curl -X POST http://localhost:8000/phi3/generate \
     -H "Authorization: Bearer $VALID_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"inputs": "Hello, how are you?"}'
```

Monitor the container logs to ensure requests are being distributed evenly.

---

## Conclusion
This document outlines a scalable approach to deploy a model across multiple GPUs with automated load balancing using Traefik. Adjust the steps as necessary for your specific deployment needs.
