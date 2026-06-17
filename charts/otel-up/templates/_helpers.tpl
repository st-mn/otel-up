{{/*
Expand the name of the chart.
*/}}
{{- define "otel-up.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "otel-up.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label.
*/}}
{{- define "otel-up.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "otel-up.labels" -}}
helm.sh/chart: {{ include "otel-up.chart" . }}
{{ include "otel-up.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "otel-up.selectorLabels" -}}
app.kubernetes.io/name: {{ include "otel-up.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-specific selector labels.
Usage: {{ include "otel-up.componentSelectorLabels" (dict "Release" .Release "Chart" .Chart "Values" .Values "component" "grafana") }}
*/}}
{{- define "otel-up.componentSelectorLabels" -}}
{{ include "otel-up.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Component fullname.
*/}}
{{- define "otel-up.componentFullname" -}}
{{- printf "%s-%s" (include "otel-up.fullname" .) .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Tempo configuration block.
*/}}
{{- define "otel-up.tempoConfig" -}}
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317

storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/blocks
    wal:
      path: /tmp/tempo/wal
{{- end }}
