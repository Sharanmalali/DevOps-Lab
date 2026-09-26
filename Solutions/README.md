# DevOps Lab — Solutions

This folder contains **complete, exercise-wise solutions** for the 10 weekly
DevOps lab exercises. Each exercise lives in its own folder with a dedicated
`README.md` that explains the solution and shows exactly how to run it.

## Repository Layout

```
DevOps-Lab/
├── Exercises/            # Official exercise briefs (read these first)
├── Solutions/            # ← you are here
│   ├── README.md         # this index
│   ├── Exercise1/
│   │   ├── README.md     # solution explanation + usage instructions
│   │   └── ...           # manifests / scripts / configs for the exercise
│   ├── Exercise2/
│   └── ... up to Exercise10
├── Assignments/          # separate course assignments
├── Notes/  References/  Syllabus/  Images/
└── README.md             # lab manual overview
```

## Exercise Index

| # | Solution | Topic | Source Brief | Status |
|---|----------|-------|--------------|--------|
| 1 | [Exercise1](Exercise1/) | Kubernetes Getting Started — Hello Pod (nginx on K8s) | [Brief](../Exercises/1-Kubernetes-Getting-Started.md) | ✅ Done |
| 2 | [Exercise2](Exercise2/) | Deploy a Flask app on Minikube using kubectl and YAML | [Brief](../Exercises/2-Minikube-Kubectl-Flask.md) | ✅ Done |
| 3 | [Exercise3](Exercise3/) | Scaling a Flask app on a single node using ReplicaSets | [Brief](../Exercises/3-Minikube-Scaling-Flask-App-with-Replicasets.md) | ✅ Done |
| 4 | [Exercise4](Exercise4/) | Docker Networking with multiple containers | [Brief](../Exercises/4-Docker-Networking.md) | ✅ Done |
| 5 | [Exercise5](Exercise5/) | Docker Security with AppArmor and Python | [Brief](../Exercises/5-Docker-Security-AppArmor.md) | ✅ Done |
| 6 | [Exercise6](Exercise6/) | Real-time operations monitoring & alerting (Prometheus + Grafana) | [Brief](../Exercises/6-Grafana-Realtime-Monitoring-of-Quick-Commerce-App.md) | ✅ Done |
| 7 | — | Introduction to CI and Jenkins installation / automation | [Brief](../Exercises/7-Jenkins-CI-Automation.md) | ⏳ Pending |
| 8 | — | Creating a "Hello World" Jenkins job from a GitHub repo | [Brief](../Exercises/8-Jenkins-Hello-World-Job.md) | ⏳ Pending |
| 9 | — | Jenkins multi-stage pipeline — deploying a Python application | [Brief](../Exercises/9-Jenkins-Multi-Stage-Pipeline.md) | ⏳ Pending |
| 10 | — | Multi-node Minikube cluster with multiple apps and ReplicaSets | [Brief](../Exercises/10-Minikube-Multi-Node-Multi-App-Minikube-Deployment.md) | ⏳ Pending |

*The "Solution" column becomes a link once that exercise has been pushed.*

## How to Use These Solutions

1. **Pick an exercise** from the table above and open its folder
   (`Solutions/ExerciseN/`).
2. **Read its `README.md` first** — it explains:
   - what the exercise asks for,
   - how the solution works (file by file),
   - prerequisites (Docker, Minikube, kubectl, Jenkins, etc.),
   - the exact commands to run the solution,
   - how to verify the expected output, and
   - how to clean everything up afterwards.
3. **Run the commands from the repo root** (paths in the READMEs assume this
   unless stated otherwise), or `cd` into the exercise folder when the README
   says so.
4. **Verify** using the check commands given in each README before moving on.

## Prerequisites (common across exercises)

| Tool | Used in | Install |
|------|---------|---------|
| Docker | 4, 5, and container-based exercises | https://docs.docker.com/get-docker/ |
| Minikube + kubectl | 1, 2, 3, 10 | https://minikube.sigs.k8s.io/docs/start/ |
| Jenkins | 7, 8, 9 | https://www.jenkins.io/download/ |
| Prometheus + Grafana | 6 | run via Docker/manifests (see Exercise 6) |

> Some exercises (e.g. AppArmor) require Linux; on Windows, run them inside
> WSL2 as noted in the exercise README.

## Submission Schedule

Solutions are pushed **every Saturday**, one exercise per week, in order:

`Aug 22 → Aug 29 → Sep 5 → Sep 12 → Sep 19 → Sep 26 → Oct 3 → Oct 10 → Oct 17 → Oct 24` (all 2026).
