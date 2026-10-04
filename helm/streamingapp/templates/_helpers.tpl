{{/* Deployment shared by all five services. Call with dict "root" . "name" <name> "svc" <values> "backend" <bool> */}}
{{- define "streamingapp.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .name }}
  labels:
    app: {{ .name }}
spec:
  replicas: {{ .svc.replicas }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: {{ .name }}
  template:
    metadata:
      labels:
        app: {{ .name }}
    spec:
      {{- if .backend }}
      initContainers:
        - name: wait-for-mongo
          image: "{{ .root.Values.imagePrefix }}/{{ .svc.image }}:{{ .svc.tag }}"
          imagePullPolicy: {{ .root.Values.imagePullPolicy }}
          command:
            - sh
            - -c
            - |
              until node -e "require('net').connect(27017,'mongo').on('connect',()=>process.exit(0)).on('error',()=>process.exit(1))"; do
                echo "waiting for mongo:27017"; sleep 2;
              done
      {{- end }}
      containers:
        - name: {{ .name }}
          image: "{{ .root.Values.imagePrefix }}/{{ .svc.image }}:{{ .svc.tag }}"
          imagePullPolicy: {{ .root.Values.imagePullPolicy }}
          ports:
            - containerPort: {{ .svc.port }}
          {{- if .backend }}
          env:
            - name: PORT
              value: {{ .svc.port | quote }}
          envFrom:
            - configMapRef:
                name: streamingapp-config
            - secretRef:
                name: streamingapp-secret
          {{- end }}
          resources:
            {{- toYaml .root.Values.resources | nindent 12 }}
          readinessProbe:
            httpGet:
              path: {{ .svc.healthPath }}
              port: {{ .svc.port }}
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: {{ .svc.healthPath }}
              port: {{ .svc.port }}
            initialDelaySeconds: 20
            periodSeconds: 20
{{- end -}}

{{/* ClusterIP Service shared by all five services. Call with dict "name" <name> "svc" <values> */}}
{{- define "streamingapp.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}-svc
  labels:
    app: {{ .name }}
spec:
  type: ClusterIP
  selector:
    app: {{ .name }}
  ports:
    - port: {{ .svc.port }}
      targetPort: {{ .svc.port }}
{{- end -}}
