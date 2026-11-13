// Package api_auth implements protocol-neutral Auth abilities.
package api_auth

import (
	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_api_key"
	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_register"
	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_session"
	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_verify_code"
)

func LoadAPIMethods() {
	api_auth_verify_code.LoadAPIMethods()
	api_auth_register.LoadAPIMethods()
	api_auth_session.LoadAPIMethods()
	api_auth_api_key.LoadAPIMethods()
}
