mock_provider "azurerm" {}

variables {
  name     = "rg-demo-dev"
  location = "germanywestcentral"
}

run "rejects_name_over_90_characters" {
  command = plan

  variables {
    name = "rg-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  }

  expect_failures = [var.name]
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "rejects_name_with_trailing_period" {
  command = plan

  variables {
    name = "rg-demo-dev."
  }

  expect_failures = [var.name]
}

run "rejects_name_with_illegal_character" {
  command = plan

  variables {
    name = "rg-demo/dev"
  }

  expect_failures = [var.name]
}

run "rejects_location_with_spaces" {
  command = plan

  variables {
    location = "Germany West Central"
  }

  expect_failures = [var.location]
}

run "rejects_empty_location" {
  command = plan

  variables {
    location = ""
  }

  expect_failures = [var.location]
}
