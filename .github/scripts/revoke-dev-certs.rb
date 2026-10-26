# يلغي شهادات التطوير (Development) القديمة بحساب Apple.
# كل بناء TestFlight يشتغل على ماك جديد، فـ Xcode يسوي شهادة تطوير جديدة كل مرة،
# وآبل تسمح بعدد محدود منها. نلغي القديمة قبل الأرشفة حتى ما يوصل للحد.
# شهادات التوزيع (Distribution) ما تنمس، ونسخ TestFlight والمتجر ما تتأثر.
#
# الاستخدام: ruby revoke-dev-certs.rb <مسار مفتاح .p8> <Key ID> <Issuer ID>
require 'openssl'
require 'json'
require 'net/http'
require 'base64'

key_path, key_id, issuer_id = ARGV
abort 'usage: revoke-dev-certs.rb KEY_PATH KEY_ID ISSUER_ID' unless issuer_id

def b64(data) = Base64.urlsafe_encode64(data, padding: false)

def token(key_path, key_id, issuer_id)
  now = Time.now.to_i
  input = [
    b64({ alg: 'ES256', kid: key_id, typ: 'JWT' }.to_json),
    b64({ iss: issuer_id, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }.to_json),
  ].join('.')
  key = OpenSSL::PKey::EC.new(File.read(key_path))
  der = key.sign(OpenSSL::Digest.new('SHA256'), input)
  # JWT يريد التوقيع r||s (64 بايت)، مو صيغة DER.
  raw = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0") }.join
  "#{input}.#{b64(raw)}"
end

def request(method, path, jwt)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = method.new(uri)
  req['Authorization'] = "Bearer #{jwt}"
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
end

jwt = token(key_path, key_id, issuer_id)
res = request(Net::HTTP::Get,
              '/v1/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200', jwt)
unless res.is_a?(Net::HTTPSuccess)
  warn "ما كدرنا نجيب الشهادات (#{res.code}): #{res.body}"
  exit 0 # ما نوقف البناء؛ إذا الحد ما واصل، الأرشفة تكمل عادي.
end

certs = JSON.parse(res.body)['data']
puts "شهادات التطوير الموجودة: #{certs.size}"
certs.each do |cert|
  attrs = cert['attributes']
  del = request(Net::HTTP::Delete, "/v1/certificates/#{cert['id']}", jwt)
  status = del.is_a?(Net::HTTPSuccess) ? 'انلغت' : "ما انلغت (#{del.code})"
  puts "  #{attrs['name']} #{attrs['serialNumber']} (#{attrs['expirationDate']}): #{status}"
end
