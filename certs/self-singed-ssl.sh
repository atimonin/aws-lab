# generate private key and enter pass phrase
openssl genrsa -out private_key.pem 2048

# create certificate signing request, enter "*.example.com" as a "Common Name", leave "challenge password" blank
openssl req -new -sha256 -key private_key.pem -out server.csr

# generate self-signed certificate for 1 year
openssl req -x509 -sha256 -days 365 -key private_key.pem -in server.csr -out server.pem

