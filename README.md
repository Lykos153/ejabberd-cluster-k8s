The relevant portion of the Deployment
```
env:
  - name: EJABBERD_CLUSTER_KUBERNETES_DISCOVERY
    value: "true"
  - name: EJABBERD_KUBERNETES_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: EJABBERD_KUBERNETES_LABEL_SELECTOR
    value: "app=ejabberd"
readinessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - /ready-probe.sh
  initialDelaySeconds: 15
  periodSeconds: 15
```

If you have RBAC enabled, you need a cluster role that can read pods.
