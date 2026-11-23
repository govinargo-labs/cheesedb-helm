{{- define "cheesedb.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "cheesedb.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "cheesedb.labels" -}}
{{ include "cheesedb.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* The names the certificate is for: the service's names, and localhost
     for kubectl port-forward. */}}
{{- define "cheesedb.dnsNames" -}}
{{- $n := include "cheesedb.fullname" . -}}
{{- $ns := .Release.Namespace -}}
{{- $names := list $n (printf "%s.%s" $n $ns) (printf "%s.%s.svc" $n $ns) (printf "%s.%s.svc.cluster.local" $n $ns) "localhost" -}}
{{- concat $names .Values.tls.extraDnsNames | toJson -}}
{{- end -}}

{{- define "cheesedb.tlsSecret" -}}
{{- if eq .Values.tls.mode "existingSecret" -}}
{{- required "tls.existingSecret is required when tls.mode is existingSecret" .Values.tls.existingSecret -}}
{{- else -}}
{{- printf "%s-tls" (include "cheesedb.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "cheesedb.adminSecret" -}}
{{- if .Values.admin.existingSecret -}}
{{- .Values.admin.existingSecret -}}
{{- else -}}
{{- printf "%s-admin" (include "cheesedb.fullname" .) -}}
{{- end -}}
{{- end -}}
