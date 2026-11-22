{{- define "gj.name" -}}{{ .Release.Name | trunc 40 | trimSuffix "-" }}{{- end -}}
{{- define "gj.fullname" -}}{{ include "gj.name" . }}{{- end -}}

{{- define "gj.labels" -}}
app.kubernetes.io/part-of: gjallar
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "gj.selector" -}}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* image: (dict "root" . "name" "api") */}}
{{- define "gj.image" -}}
{{ .root.Values.image.registry }}/gjallar-{{ .name }}:{{ .tag | default .root.Values.image.tag | default .root.Chart.AppVersion }}
{{- end -}}

{{- define "gj.natsUrl" -}}
{{- if .Values.nats.enabled -}}nats://{{ include "gj.fullname" . }}-nats:4222{{- else -}}{{ required "nats.externalUrl is required when nats.enabled=false" .Values.nats.externalUrl }}{{- end -}}
{{- end -}}

{{- define "gj.dbSecret" -}}
{{- if .Values.postgresql.existingSecret -}}{{ .Values.postgresql.existingSecret }}{{- else -}}{{ include "gj.fullname" . }}-db{{- end -}}
{{- end -}}

{{- define "gj.grypeUrl" -}}
{{- if .Values.grypeDB.updateUrl -}}{{ .Values.grypeDB.updateUrl }}{{- else if .Values.grypeDB.enabled -}}http://{{ include "gj.fullname" . }}-grype-db:8080/databases{{- end -}}
{{- end -}}

{{/* Common env for every Gjallar process */}}
{{- define "gj.natsSecret" -}}
{{- .Values.nats.tokenSecret | default (printf "%s-nats" (include "gj.fullname" .)) -}}
{{- end -}}
{{/* Services: full bus access (user "gjallar", or the shared token in auth=token mode). */}}
{{- define "gj.commonEnv" -}}
{{- if eq .Values.nats.auth "users" }}
- { name: GJALLAR_NATS_USER, value: gjallar }
{{- end }}
- name: GJALLAR_NATS_TOKEN
  valueFrom: { secretKeyRef: { name: {{ include "gj.natsSecret" . }}, key: token, optional: true } }
{{ include "gj.baseEnv" . }}
{{- end -}}
{{/* Agents: user "agent", limited to inventory and runtime data (templates/nats.yaml). */}}
{{- define "gj.agentEnv" -}}
{{- if eq .Values.nats.auth "users" }}
- { name: GJALLAR_NATS_USER, value: agent }
- name: GJALLAR_NATS_PASSWORD
  valueFrom: { secretKeyRef: { name: {{ include "gj.natsSecret" . }}, key: agent-password, optional: true } }
{{- else }}
- name: GJALLAR_NATS_TOKEN
  valueFrom: { secretKeyRef: { name: {{ include "gj.natsSecret" . }}, key: token, optional: true } }
{{- end }}
{{- if .Values.nats.caSecret }}
- { name: GJALLAR_NATS_CA, value: /etc/gjallar/nats-ca/ca.crt }
{{- end }}
{{ include "gj.baseEnv" . }}
{{- end -}}
{{- define "gj.baseEnv" -}}
- name: GJALLAR_NATS_URL
  value: {{ include "gj.natsUrl" . | quote }}
- name: GJALLAR_LOG_LEVEL
  value: {{ .Values.observability.logLevel | quote }}
{{- with .Values.observability.otlpEndpoint }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ . | quote }}
{{- end }}
- name: POD_NAMESPACE
  valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
{{- end -}}

{{- define "gj.podSecurity" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
fsGroup: 65532
seccompProfile: { type: RuntimeDefault }
{{- end -}}

{{- define "gj.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities: { drop: [ALL] }
{{- end -}}

{{- define "gj.pullSecrets" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . | indent 2 }}
{{- end }}
{{- end -}}

{{- define "gj.analyticsEnv" -}}
{{- $s3 := .Values.analytics.s3 -}}
{{ include "gj.commonEnv" . }}
- { name: OTEL_SERVICE_NAME, value: gjallar-analytics }
{{- with .Values.auth.issuer }}
- { name: GJALLAR_OIDC_ISSUER, value: {{ . | quote }} }  # Flight SQL bearer tokens
{{- end }}
- { name: GJALLAR_OIDC_CLIENT_ID, value: {{ .Values.auth.clientId | quote }} }
- { name: GJALLAR_FLIGHT_ROLES, value: {{ join "," .Values.tenancy.globalRoles | quote }} }
- { name: GJALLAR_LAKE_MODE, value: {{ .Values.analytics.mode | quote }} }
- { name: GJALLAR_LAKE_DATA, value: {{ $s3.dataPath | default "/data/lake/" | quote }} }
- { name: GJALLAR_LAKE_FLUSH, value: {{ .Values.analytics.flushInterval | quote }} }
- { name: GJALLAR_LAKE_RETAIN, value: {{ .Values.analytics.retainSnapshots | quote }} }
{{- if eq .Values.analytics.mode "ducklake" }}
- name: GJALLAR_LAKE_CATALOG
  valueFrom: { secretKeyRef: { name: {{ include "gj.dbSecret" . }}, key: LAKE_CATALOG } }
{{- end }}
{{- if $s3.dataPath }}
- { name: GJALLAR_S3_ENDPOINT, value: {{ $s3.endpoint | quote }} }
- { name: GJALLAR_S3_REGION, value: {{ $s3.region | quote }} }
- { name: GJALLAR_S3_USE_SSL, value: {{ $s3.useSSL | quote }} }
- name: GJALLAR_S3_ACCESS_KEY
  valueFrom: { secretKeyRef: { name: {{ required "analytics.s3.existingSecret is required for S3" $s3.existingSecret }}, key: access-key } }
- name: GJALLAR_S3_SECRET_KEY
  valueFrom: { secretKeyRef: { name: {{ $s3.existingSecret }}, key: secret-key } }
{{- end }}
{{- end -}}
