{{- define "smart-log-analyzer.image" -}}
{{ .Values.imageRegistry }}/{{ .Values.namespace }}/{{ .name }}:latest
{{- end -}}

{{- define "smart-log-analyzer.labels" -}}
app: {{ .name }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/part-of: smart-log-analyzer
app.kubernetes.io/managed-by: Helm
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
