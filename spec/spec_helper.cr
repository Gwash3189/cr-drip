require "spec"
require "../src/cr-drip"

# Ensure every example starts with an empty registry so specs are isolated
Spec.before_each do
  Drip.reset_all
end
