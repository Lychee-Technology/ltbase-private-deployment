package naming

import (
	"fmt"
	"strings"
)

func StackPrefix(project, stack string) string {
	return sanitize(fmt.Sprintf("%s-%s", project, stack))
}

func ResourceName(project, stack, suffix string) string {
	base := StackPrefix(project, stack)
	if strings.TrimSpace(suffix) == "" {
		return base
	}
	return sanitize(base + "-" + suffix)
}

func AliasName(stack string) string {
	return sanitize(stack)
}

func CloudflareRecordName(fqdn, zoneName string) string {
	name := strings.TrimSuffix(strings.TrimSpace(fqdn), ".")
	zone := strings.TrimSuffix(strings.TrimSpace(zoneName), ".")
	switch {
	case name == "":
		return "@"
	case zone == "":
		return name
	case strings.EqualFold(name, zone):
		return "@"
	case strings.HasSuffix(strings.ToLower(name), "."+strings.ToLower(zone)):
		return strings.TrimSuffix(name, "."+zone)
	default:
		return name
	}
}

func sanitize(value string) string {
	parts := strings.FieldsFunc(strings.ToLower(strings.TrimSpace(value)), func(r rune) bool {
		switch {
		case r >= 'a' && r <= 'z':
			return false
		case r >= '0' && r <= '9':
			return false
		case r == '-':
			return false
		default:
			return true
		}
	})
	return strings.Trim(strings.Join(parts, "-"), "-")
}
