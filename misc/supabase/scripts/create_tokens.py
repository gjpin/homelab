# References:
# https://supabase.com/docs/guides/self-hosting/docker#generate-api-keys
# https://github.com/jpadilla/pyjwt/
# pip install PyJWT

import secrets
import jwt

# Generate random hex strings
secret = secrets.token_hex(40)
print("secret: " + secret)

# Generate ANON_KEY token
anon_token = jwt.encode(
    {"role": "anon", "iss": "supabase", "iat": 1738800000, "exp": 1896566400},
    secret,
    algorithm="HS256",
)
print("anon_token: " + anon_token)

# Generate SERVICE_KEY token
service_role_token = jwt.encode(
    {"role": "service_role", "iss": "supabase", "iat": 1738800000, "exp": 1896566400},
    secret,
    algorithm="HS256",
)
print("service_role_token: " + service_role_token)
