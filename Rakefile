# Standalone Rake — no Rails. Loads every .rake under lib/tasks.
# The task backlog machinery (lib/tasks/tasks.rake) is pure Ruby and shared,
# verbatim, with every venture this repo scaffolds. lib/tasks/ventures.rake is
# holdco-only: it manages the portfolio registry and stamps out new operators.
Dir.glob(File.join(__dir__, "lib", "tasks", "*.rake")).sort.each { |f| load f }

task default: %i[]
