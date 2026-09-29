mock_provider "aws" {}

run "computed_network_external_groups" {
  command = plan
  module { source = "./tests/fixtures/computed-network" }
}
