{{- define "platform-demo.name" -}}
platform-demo
{{- end }}

{{- define "platform-demo.fullname" -}}
{{ include "platform-demo.name" . }}-app
{{- end }}