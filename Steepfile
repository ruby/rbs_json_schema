D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"

  library "rbs", "json", "uri", "pathname", "strscan", "tsort", "optparse", "logger", "monitor", "rubygems", "net-http"

  configure_code_diagnostics do |hash|
    hash[D::Ruby::MethodDefinitionMissing] = :hint
  end
end

target :test do
  signature "sig"
  check "test"

  library "rbs", "json", "uri", "pathname", "strscan", "tsort", "optparse", "logger", "monitor", "rubygems", "tmpdir"
end
