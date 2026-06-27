package services

func authorizedRoutes(authorizerName string, routeKeys ...string) []routeSpec {
	routes := make([]routeSpec, len(routeKeys))
	for i, key := range routeKeys {
		routes[i] = routeSpec{RouteKey: key, AuthorizerName: authorizerName}
	}
	return routes
}

func preflightRoutes() []routeSpec {
	return []routeSpec{
		{RouteKey: "OPTIONS /"},
		{RouteKey: "OPTIONS /{proxy+}"},
	}
}

func buildAPIRouteSpecs() []routeSpec {
	business := authorizedRoutes("LTBase",
		"GET /api/ai/v1/notes",
		"POST /api/ai/v1/notes",
		"GET /api/ai/v1/notes/{note_id}",
		"PUT /api/ai/v1/notes/{note_id}",
		"DELETE /api/ai/v1/notes/{note_id}",
		"GET /api/ai/v1/notes/{note_id}/model_sync",
		"POST /api/ai/v1/notes/{note_id}/model_sync",

		"POST /api/ai/v1/sessions",
		"GET /api/ai/v1/sessions/{session_id}",
		"GET /api/ai/v1/sessions/{session_id}/messages",
		"POST /api/ai/v1/sessions/{session_id}/messages",
		"POST /api/ai/v1/operations",

		"POST /api/ai/v1/agent/sessions",
		"GET /api/ai/v1/agent/sessions/{session_id}",
		"DELETE /api/ai/v1/agent/sessions/{session_id}",
		"GET /api/ai/v1/agent/sessions/{session_id}/turns",
		"POST /api/ai/v1/agent/sessions/{session_id}/turns",
		"GET /api/ai/v1/agent/sessions/{session_id}/turns/{turn_id}/citations",

		"POST /api/ai/v1/intent-to-action/plans",
		"POST /api/ai/v1/intent-to-action/executions",
		"GET /api/ai/v1/intent-to-action/executions/{execution_id}",

		"POST /api/ai/v1/governance/actions/execute",

		"POST /api/ai/v1/compliance/decisions",

		"GET /api/v1/deepping",
		"GET /api/v1/schemas",
		"GET /api/v1/tools",
		"GET /api/v1/audit_records",
		"GET /api/v1/search",
		"POST /api/v1/advanced_query",
		"GET /api/v1/{schema_name}",
		"POST /api/v1/{schema_name}",
		"DELETE /api/v1/{schema_name}",
		"GET /api/v1/{schema_name}/{row_id}",
		"PUT /api/v1/{schema_name}/{row_id}",
		"DELETE /api/v1/{schema_name}/{row_id}",

		"GET /api/ltflow/v1/tasks",
		"GET /api/ltflow/v1/tasks/{task_id}",
		"GET /api/ltflow/v1/instances",
		"POST /api/ltflow/v1/instances",
		"GET /api/ltflow/v1/instances/{instance_id}",
		"POST /api/ltflow/v1/instances/{instance_id}/events",
		"GET /api/ltflow/v1/instances/{instance_id}/history",

		"POST /api/sys/v1/discovery/reachable",
		"POST /api/sys/v1/discovery/paths",

		"GET /api/sys/v1/ontology/object-types",
		"GET /api/sys/v1/ontology/object-types/{type_name}",
		"GET /api/sys/v1/ontology/link-types",
		"GET /api/sys/v1/ontology/action-types",
		"GET /api/sys/v1/ontology/objects/{type_name}/{row_id}",
		"POST /api/sys/v1/ontology/objects/{type_name}/search",
		"POST /api/sys/v1/ontology/objects/{type_name}/{row_id}/reachable",
		"GET /api/sys/v1/ontology/objects/{type_name}/{row_id}/actions",
		"GET /api/sys/v1/ontology/objects/{type_name}/{row_id}/provenance",

		"GET /api/sys/v1/governance/entities/{entity}/capabilities",
		"GET /api/sys/v1/governance/capabilities/{capability}",
		"GET /api/sys/v1/governance/policies/{policy}/capabilities",
		"GET /api/sys/v1/governance/claims",
		"POST /api/sys/v1/governance/claims",
		"POST /api/sys/v1/governance/claims/{claim_id}/approve",
		"POST /api/sys/v1/governance/claims/{claim_id}/reject",
		"GET /api/sys/v1/governance/events",
		"POST /api/sys/v1/governance/evidence",
		"GET /api/sys/v1/governance/evidence/{evidence_id}/gaps",
		"GET /api/sys/v1/governance/evidence/{evidence_id}/expired",
		"POST /api/sys/v1/governance/evidence/{evidence_id}/validate",
		"POST /api/sys/v1/governance/monitoring/re-evaluate",

		"GET /api/sys/v1/compliance/entities/{entity}",
		"GET /api/sys/v1/compliance/capabilities/{capability}",
		"GET /api/sys/v1/compliance/policies/{policy}",

		"GET /api/v1/semantic/resources",
		"GET /api/v1/semantic/resources/{resource_id}",
		"GET /api/v1/semantic/lineage/{resource_id}",
	)
	return append(business, preflightRoutes()...)
}

func buildControlPlaneRouteSpecs() []routeSpec {
	var business []routeSpec
	for _, prefix := range []string{"/api/v1", "/api/control-plane/v1"} {
		p := func(path string) string { return prefix + path }
		business = append(business, authorizedRoutes("LTBase",
			"GET "+p("/status"),
			"GET "+p("/schema/status"),
			"GET "+p("/workflows"),

			"POST "+p("/repair/dry-run"),
			"POST "+p("/repair/apply"),

			"GET "+p("/catalogs/capabilities"),
			"PUT "+p("/catalogs/capabilities"),
			"GET "+p("/catalogs/action-templates"),
			"PUT "+p("/catalogs/action-templates"),
			"GET "+p("/catalogs/assistant-roles"),
			"PUT "+p("/catalogs/assistant-roles"),

			"GET "+p("/compliance-profile"),
			"PUT "+p("/compliance-profile"),

			"GET "+p("/auth-config"),
			"GET "+p("/auth/config"),

			"GET "+p("/referrals"),
			"POST "+p("/referrals"),
			"PATCH "+p("/referrals/{code}"),
			"DELETE "+p("/referrals/{code}"),
			"POST "+p("/referrals/{code}/disable"),

			"GET "+p("/auth/referrals"),
			"POST "+p("/auth/referrals"),
			"PATCH "+p("/auth/referrals/{code}"),
			"DELETE "+p("/auth/referrals/{code}"),
			"POST "+p("/auth/referrals/{code}/disable"),

			"GET "+p("/auth/users"),
			"GET "+p("/auth/users/{user_id}"),
			"PATCH "+p("/auth/users/{user_id}"),
			"PUT "+p("/auth/users/{user_id}/roles/{role_id}"),
			"DELETE "+p("/auth/users/{user_id}/roles/{role_id}"),

			"GET "+p("/auth/roles"),
			"POST "+p("/auth/roles"),
			"GET "+p("/auth/roles/{role_id}"),
			"PATCH "+p("/auth/roles/{role_id}"),
			"DELETE "+p("/auth/roles/{role_id}"),

			"GET "+p("/auth/policies"),
			"POST "+p("/auth/policies"),
			"GET "+p("/auth/policies/{policy_id}"),
			"PATCH "+p("/auth/policies/{policy_id}"),
			"DELETE "+p("/auth/policies/{policy_id}"),

			"GET "+p("/auth/binding-policies"),
			"POST "+p("/auth/binding-policies"),
			"PATCH "+p("/auth/binding-policies/{policy_id}"),
			"DELETE "+p("/auth/binding-policies/{policy_id}"),

			"GET "+p("/auth/principals/{principal_type}/{principal_id}/policies"),
			"PUT "+p("/auth/principals/{principal_type}/{principal_id}/policies/{policy_id}"),
			"DELETE "+p("/auth/principals/{principal_type}/{principal_id}/policies/{policy_id}"),

			"GET "+p("/org/units"),
			"POST "+p("/org/units"),
			"GET "+p("/org/units/{ou_id}"),
			"PATCH "+p("/org/units/{ou_id}"),
			"DELETE "+p("/org/units/{ou_id}"),
			"GET "+p("/org/units/{ou_id}/users"),
			"PUT "+p("/org/units/{ou_id}/users/{user_id}"),
			"GET "+p("/org/units/{ou_id}/policies"),
			"PUT "+p("/org/units/{ou_id}/policies/{policy_id}"),
			"DELETE "+p("/org/units/{ou_id}/policies/{policy_id}"),

			"GET "+p("/org/users/{user_id}/manager"),
			"PUT "+p("/org/users/{user_id}/manager"),
			"DELETE "+p("/org/users/{user_id}/manager"),
			"GET "+p("/org/users/{user_id}/direct-reports"),
			"GET "+p("/org/charts"),
		)...)
	}
	return append(business, preflightRoutes()...)
}

func buildAuthRouteSpecs(providerCfg AuthProviderConfig) []routeSpec {
	routes := []routeSpec{
		{RouteKey: "GET /api/v1/auth/health"},
		{RouteKey: "POST /api/v1/auth/refresh", AuthorizerName: "LTBaseRefresh"},
		{RouteKey: "POST /api/v1/auth/revoke", AuthorizerName: "LTBase"},
		{RouteKey: "GET /api/v1/auth/profile/{user_id}", AuthorizerName: "LTBase"},
	}
	for _, provider := range providerCfg.Providers {
		if provider.EnableIDBinding {
			routes = append(routes, routeSpec{RouteKey: "POST /api/v1/id_bindings/" + provider.Name, AuthorizerName: provider.Name})
		}
		if provider.EnableLogin {
			routes = append(routes, routeSpec{RouteKey: "POST /api/v1/login/" + provider.Name, AuthorizerName: provider.Name})
		}
	}
	routes = append(routes, preflightRoutes()...)
	return routes
}
