# One-file-per-task backlog. Each task is a markdown file with YAML frontmatter
# under `tasks/`, so parallel agents that create/finish *different* tasks touch
# *different* files and never race on a push. `TASKS.md` is a GENERATED index
# (rake tasks:index) — don't hand-edit it.
#
# Frontmatter schema (see tasks/_template.md):
#   id        stable, sortable slug (also the filename: <id>.md)
#   title     short imperative title
#   priority  P0 | P1 | P2 | untriaged   (untriaged = created via `rake task`, awaiting triage)
#   status    open | wip | blocked | done
#   domain    Eng | Design | Product | Marketing | Finance | Legal | Ops | Launch-blocking | untriaged
#   created   YYYY-MM-DD
#   updated   YYYY-MM-DD            (optional)
#   blocked_on  user                (optional flag for user-blocked items)
# The markdown body holds the full description + sub-bullets, verbatim.

require "yaml"
require "date"
require "fileutils"

# Standalone (no ActiveSupport): minimal `String#presence` used by the editor flow.
# Guarded so it's a no-op if this ever loads alongside Rails.
class String
  def presence = strip.empty? ? nil : self
end unless String.method_defined?(:presence)

namespace :tasks do
  TASKS_DIR = "tasks".freeze
  INDEX_FILE = "TASKS.md".freeze
  HEADER_FILE = "lib/tasks/templates/tasks_header.md".freeze

  # Domains in render order. Index sections appear in this order.
  DOMAINS = %w[Launch-blocking Eng Design Product Marketing Finance Legal Ops].freeze

  # Map a TASKS.md "## emoji Heading" (normalized) to a domain label.
  DOMAIN_FROM_HEADING = {
    "launch-blocking" => "Launch-blocking",
    "engineering" => "Eng",
    "design" => "Design",
    "product" => "Product",
    "marketing & gtm" => "Marketing",
    "marketing" => "Marketing",
    "finance" => "Finance",
    "legal & compliance" => "Legal",
    "legal" => "Legal",
    "ops & support" => "Ops",
    "ops" => "Ops"
  }.freeze

  EMOJI = {
    "Launch-blocking" => "🔴", "Eng" => "🟠", "Design" => "🎨", "Product" => "🧭",
    "Marketing" => "📣", "Finance" => "💰", "Legal" => "⚖️", "Ops" => "🛟"
  }.freeze
  HEADING = {
    "Launch-blocking" => "Launch-blocking (P0)", "Eng" => "Engineering", "Design" => "Design",
    "Product" => "Product", "Marketing" => "Marketing & GTM", "Finance" => "Finance",
    "Legal" => "Legal & Compliance", "Ops" => "Ops & Support"
  }.freeze

  CHECKBOX_TO_STATUS = { " " => "open", "~" => "wip", "x" => "done", "!" => "blocked" }.freeze
  STATUS_TO_CHECKBOX = { "open" => " ", "wip" => "~", "done" => "x", "blocked" => "!" }.freeze
  STATUS_ORDER = { "open" => 0, "wip" => 1, "blocked" => 2, "done" => 3 }.freeze
  PRIORITY_ORDER = { "P0" => 0, "P1" => 1, "P2" => 2 }.freeze

  # Untriaged tasks (created via the editor flow) carry this sentinel for
  # priority *and* domain until the operating agent assigns real values. They
  # render in the "Needs triage" section at the top of TASKS.md, not in a domain.
  UNTRIAGED = "untriaged".freeze

  # ---- task-file store -------------------------------------------------------

  module Store
    module_function

    def files
      Dir.glob(File.join(TASKS_DIR, "*.md")).reject { |p| File.basename(p).start_with?("_") }.sort
    end

    def all = files.map { |path| read(path) }

    # => { meta: {string keys}, body: "..", path: ".." }
    def read(path)
      raw = File.read(path)
      if raw.start_with?("---\n")
        _, fm, body = raw.split(/^---\n/, 3)
        meta = YAML.safe_load(fm, permitted_classes: [ Date ]) || {}
      else
        meta = {}
        body = raw
      end
      { meta: meta.transform_keys(&:to_s).transform_values { |v| v.is_a?(Date) ? v.iso8601 : v },
        body: body.to_s.strip, path: path }
    end

    def write(id:, meta:, body:)
      FileUtils.mkdir_p(TASKS_DIR)
      order = %w[id title priority status domain created updated blocked_on]
      fm = {}
      order.each { |k| fm[k] = meta[k] unless meta[k].nil? || meta[k] == "" }
      meta.each { |k, v| fm[k] = v unless order.include?(k) || v.nil? || v == "" }
      path = File.join(TASKS_DIR, "#{id}.md")
      File.write(path, "#{YAML.dump(fm)}---\n\n#{body.strip}\n")
      path
    end

    def find(id)
      path = File.join(TASKS_DIR, "#{id}.md")
      raise "No task with id #{id.inspect} (looked for #{path})" unless File.exist?(path)

      read(path)
    end

    # Unique slug from a title; suffix -2, -3… on collision.
    def slug_for(title)
      base = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 60].to_s
      base = "task" if base.empty?
      slug = base
      n = 1
      while File.exist?(File.join(TASKS_DIR, "#{slug}.md"))
        n += 1
        slug = "#{base}-#{n}"
      end
      slug
    end
  end

  def sort_key(task)
    m = task[:meta]
    [ PRIORITY_ORDER.fetch(m["priority"], 9), STATUS_ORDER.fetch(m["status"], 9), m["id"].to_s ]
  end

  def untriaged?(task) = task[:meta]["priority"] == UNTRIAGED || task[:meta]["domain"] == UNTRIAGED

  def domain_heading(domain) = "#{EMOJI[domain]} #{HEADING.fetch(domain, domain)}"

  PLACEHOLDER_BODY = "_(no description in source)_".freeze

  # Render one task as a "- [x] (P1) Title" line. A short single-line body becomes
  # an inline "— context"; multi-line bodies render indented underneath, verbatim.
  def render_line(task)
    m = task[:meta]
    box = STATUS_TO_CHECKBOX.fetch(m["status"], " ")
    prio = PRIORITY_ORDER.key?(m["priority"]) ? "(#{m['priority']}) " : ""
    out = +"- [#{box}] #{prio}#{m['title']}"

    body = task[:body].to_s.strip
    body = "" if body == PLACEHOLDER_BODY
    lines = body.lines.map(&:rstrip)
    nonblank = lines.reject { |l| l.strip.empty? }

    if nonblank.size == 1 && lines.size == 1
      out << " — #{nonblank.first.strip}"
      out << "\n"
    else
      out << "\n"
      lines.each { |l| out << (l.strip.empty? ? "\n" : "        #{l}\n") }
    end
    out
  end

  # ---- tasks:import ----------------------------------------------------------

  TITLE_MAX = 72                       # cap so titles stay scannable one-liners.

  # Derive a clean, short title from a (possibly wrapped, markdown-laced) lead.
  # The migration's bug was taking the first *wrapped* line verbatim, so titles
  # ended mid-clause ("… create a **Discord"). We instead cut at the first
  # sentence end / em-dash / colon-clause, strip leading markdown, and length-cap
  # at a word boundary so a future import can't reproduce that.
  def clean_title(raw)
    text = raw.to_s.gsub(/\s+/, " ").strip
    text = text.delete("*")                                   # drop markdown bold
    text = text.sub(/\A\[([^\]]+)\]\([^)]*\)/, '\1')          # [label](url) -> label
    # First sentence-ish unit: stop at a real sentence period, an em-dash aside,
    # or a "Heading: detail" colon — whichever comes first.
    head = text[/\A.*?(?=(?:\.\s)|(?:\.\z)|\s—\s|: )/, 0] || text
    head = head.strip
    head = text.strip if head.empty?
    head = truncate_at_word(head, TITLE_MAX)
    head.sub(/[\s,:;(—-]+\z/, "").strip                       # no dangling punctuation
  end

  # The slice of `lead` left over after `title` was carved off its front — the
  # bullet line's own text that didn't fit in the title, so it isn't dropped.
  # Compares on markdown-stripped text (clean_title strips markdown) and trims
  # the leading separator left dangling (". ", ": ", "— ").
  def clause_after(lead, title)
    plain = lead.to_s.gsub(/\s+/, " ").strip.delete("*")
    plain = plain.sub(/\A\[([^\]]+)\]\([^)]*\)/, '\1')
    rest = plain.delete_prefix(title.to_s.strip)
    rest.sub(/\A[\s.:;,—-]+/, "").strip
  end

  # Truncate to <= max characters on a word boundary (no trailing partial word).
  def truncate_at_word(str, max)
    return str if str.length <= max

    cut = str[0, max]
    cut = cut.sub(/\s\S*\z/, "") if str[max] && str[max] != " "
    cut.strip
  end


  # Strip the common leading indentation off a block of lines (so the stored
  # body is clean markdown; tasks:index re-indents it consistently). Nesting is
  # preserved relative to the shallowest line.
  def dedent(lines)
    present = lines.reject { |l| l.strip.empty? }
    return lines if present.empty?

    min = present.map { |l| l[/\A */].length }.min
    lines.map { |l| l.strip.empty? ? "" : l[min..] }
  end

  # Parse the current TASKS.md into [{checkbox, priority, title, body, domain, section}].
  def parse_index(path)
    section = nil          # domain label, :blocked, :shipped, :skip, or nil
    domain = nil
    current = nil
    footer = false         # inside a "_…_" section-footer roll-up
    items = []

    finish = -> { items << current if current; current = nil }

    File.readlines(path, chomp: true).each do |line|
      # A whole-line italic "_…_" roll-up (e.g. "_Resolved: …_") is a section
      # footer, not task content — skip it and any wrapped continuation.
      if footer
        footer = false if line.rstrip.end_with?("_")
        next
      end
      if line.match?(/\A_\S/)
        finish.call
        footer = !line.rstrip.end_with?("_")
        next
      end

      # Only top-level "## Heading" switches section/domain. Deeper "### …"
      # sub-headings (e.g. "### Payments & fulfillment") just group tasks within
      # a domain — end the current task but keep the section.
      if line.match?(/\A###+\s+/)
        finish.call
        next
      end

      if (h = line[/\A##\s+(.+)\z/, 1])
        finish.call
        key = h.downcase.gsub(/[^a-z&\- ]/, "").strip
        if key.include?("blocked on the user")
          section = :blocked
        elsif key.include?("recently shipped")
          section = :shipped
        elsif key.include?("how to use") || key.include?("task format")
          section = :skip
        elsif (d = DOMAIN_FROM_HEADING[key] || DOMAIN_FROM_HEADING.find { |k, _| key.start_with?(k) }&.last)
          section = :domain
          domain = d
        else
          section = nil
        end
        next
      end

      next if section.nil? || section == :skip

      # A "---" horizontal rule ends the current task; it isn't task content.
      if line.match?(/\A---+\s*\z/)
        finish.call
        next
      end

      if (m = line.match(/\A- \[(.)\] (?:\((P\d)\) )?(.*)\z/))
        finish.call
        current = { checkbox: m[1], priority: m[2], title_line: m[3], extra: [],
                    section: section, domain: domain }
      elsif section == :shipped && (m = line.match(/\A- (.+)\z/))
        # Recently-shipped entries are checkbox-less one-liners; capture each as a
        # done task so its text isn't lost.
        finish.call
        current = { checkbox: "x", priority: nil, title_line: m[1], extra: [],
                    section: section, domain: domain }
      elsif current
        current[:extra] << line
      end
    end
    finish.call
    items
  end

  desc "Split the current TASKS.md into one file per task under tasks/ (FORCE=1 to overwrite)"
  task :import do
    existing = Store.files
    if existing.any? && ENV["FORCE"] != "1"
      abort "tasks/ already has #{existing.size} task file(s). Re-run with FORCE=1 to overwrite."
    end
    FileUtils.rm_f(existing)

    created = Date.today.iso8601
    count = 0

    parse_index(INDEX_FILE).each do |item|
      title_line = item[:title_line].to_s
      leftover = nil
      if item[:section] == :shipped
        # A shipped one-liner is its own summary — keep it whole as the title.
        title = title_line.strip
        rest = nil
      else
        pre, rest = title_line.split(/\s+—\s+/, 2)
        pre = title_line if pre.to_s.strip.empty?
        # Derive a clean title from the bullet's own line: clean_title cuts at the
        # first sentence end / em-dash / colon-clause and strips markdown, so a
        # wrapped run-on can't bleed mid-clause into the title. Any remainder of
        # that line is real content → keep it as the first body line so nothing is
        # lost. The "- context" half (after an em-dash) still becomes body too.
        title = clean_title(pre)
        leftover = clause_after(pre, title)
      end

      body_lines = []
      body_lines << rest.strip if rest && !rest.strip.empty?
      body_lines << leftover if leftover && !leftover.empty?
      body_lines.concat(dedent(item[:extra]))
      body = body_lines.join("\n").strip
      body = PLACEHOLDER_BODY if body.empty?

      status =
        case item[:section]
        when :shipped then "done"
        else CHECKBOX_TO_STATUS.fetch(item[:checkbox], "open")
        end
      domain = item[:domain] || (item[:section] == :blocked ? "Launch-blocking" : "Ops")
      priority = item[:priority] || "P1"

      id = Store.slug_for(title)
      meta = { "id" => id, "title" => title, "priority" => priority, "status" => status,
               "domain" => domain, "created" => created }
      meta["blocked_on"] = "user" if item[:section] == :blocked
      Store.write(id: id, meta: meta, body: body)
      count += 1
    end

    puts "Imported #{count} task(s) into #{TASKS_DIR}/."
  end

  # ---- tasks:index -----------------------------------------------------------

  desc "Regenerate TASKS.md from the task files under tasks/"
  task :index do
    tasks = Store.all
    out = +File.read(HEADER_FILE)
    out << "\n" unless out.end_with?("\n\n")

    # Untriaged tasks (editor flow) surface at the very top so the agent assigns
    # priority + domain. They live in no domain section until triaged.
    needs_triage = tasks.select { |t| untriaged?(t) && t[:meta]["status"] != "done" }
                        .sort_by { |t| t[:meta]["created"].to_s }
    unless needs_triage.empty?
      out << "## 🆕 Needs triage\n\n"
      out << "New tasks (created via `rake task`) awaiting priority + domain. Triage with\n" \
             "`rake tasks:triage[id,P1,Eng]`, then they move into a domain section below.\n\n"
      needs_triage.each { |t| out << render_line(t) }
      out << "\n---\n\n"
    end

    by_domain = tasks.group_by { |t| t[:meta]["domain"] }
    DOMAINS.each do |domain|
      group = (by_domain[domain] || [])
              .reject { |t| t[:meta]["status"] == "done" || t[:meta]["blocked_on"] }
              .sort_by { |t| sort_key(t) }
      next if group.empty?

      out << "## #{domain_heading(domain)}\n\n"
      group.each { |t| out << render_line(t) }
      out << "\n"
    end

    out << "---\n\n## 🚧 Blocked on the user\n\n"
    out << "Surfaced here so they're not lost in the sections above. Do the autonomous work; nudge\n" \
           "the user on these.\n\n"
    tasks.select { |t| t[:meta]["blocked_on"] }.sort_by { |t| sort_key(t) }
         .each { |t| out << render_line(t) }
    out << "\n"

    out << "---\n\n## Recently shipped\n\n"
    out << "Short memory aid only — git history is the full record. Trim as this grows.\n\n"
    tasks.select { |t| t[:meta]["status"] == "done" }
         .sort_by { |t| [ [ t[:meta]["updated"].to_s, t[:meta]["created"].to_s ].max, t[:meta]["id"].to_s ] }
         .reverse
         .each do |t|
      summary = t[:body].to_s.lines.first.to_s.strip
      summary = "" if summary == PLACEHOLDER_BODY
      out << "- #{t[:meta]['title']}#{summary.empty? ? '' : " — #{summary}"}\n"
    end
    out << "\n"

    File.write(INDEX_FILE, out)
    puts "Wrote #{INDEX_FILE} from #{tasks.size} task file(s)."
  end

  # ---- git-commit-style editor flow ------------------------------------------

  # The prefilled buffer the editor opens on: empty title/body, then `#` help
  # lines (stripped on save) explaining the format. Mirrors `git commit`.
  EDITOR_TEMPLATE = <<~MD.freeze

    # First line above is the TITLE. Leave a blank line, then write the
    # description/body below — like a git commit message.
    #
    # Lines starting with '#' are comments and will be ignored. A file with no
    # title creates nothing. Priority and domain are left UNTRIAGED on purpose;
    # the operating agent triages them later (rake tasks:triage[id,P1,Eng]).
  MD

  # Split an edited buffer into [title, body]. The first non-empty, non-comment
  # line is the title; everything after it (minus comment lines) is the body.
  # Returns ["", ""] for an empty/all-comment buffer (caller treats as abort).
  def parse_task_input(text)
    lines = text.to_s.lines.map(&:rstrip).reject { |l| l.lstrip.start_with?("#") }
    lines.shift while lines.first&.strip&.empty?   # drop leading blanks
    return [ "", "" ] if lines.empty?

    title = lines.shift.strip
    body = lines.join("\n").strip
    [ title, body ]
  end

  # Open $VISUAL/$EDITOR (fallback: vi) on a tempfile prefilled with `template`,
  # and return the saved contents. Returns nil when no interactive editor is
  # available so callers can fall back to ENV. Factored out so tests never spawn
  # an editor.
  def edit_in_editor(template)
    editor = ENV["VISUAL"].to_s.strip
    editor = ENV["EDITOR"].to_s.strip if editor.empty?
    editor = "vi" if editor.empty? && $stdin.tty?
    return nil if editor.empty?

    require "tempfile"
    Tempfile.create([ "task", ".md" ]) do |f|
      f.write(template)
      f.flush
      system("#{editor} #{f.path}") || abort("Editor #{editor.inspect} exited non-zero; aborting.")
      File.read(f.path)
    end
  end

  # ---- mutators --------------------------------------------------------------

  desc "Create a new task. No args -> open $EDITOR (title on line 1, body below); " \
       "explicit args set priority/domain directly: rake tasks:new[title,priority,domain]"
  task :new, %i[title priority domain] do |_t, args|
    if args[:title].to_s.strip.empty?
      # No positional title: open an editor (git-commit style). Untriaged by
      # default — the operating agent triages priority/domain later. TITLE/BODY
      # env are the non-interactive fallback (CI, no $EDITOR).
      buffer = edit_in_editor(EDITOR_TEMPLATE)
      title, body = buffer ? parse_task_input(buffer) : [ "", "" ]
      title = (title.presence || ENV["TITLE"]).to_s.strip
      body = (body.presence || ENV["BODY"]).to_s.strip
      abort "No title — nothing created. (Set EDITOR, or pass TITLE=… / rake tasks:new[\"title\"].)" if title.empty?
      priority = UNTRIAGED
      domain = UNTRIAGED
    else
      # Explicit args (scripts/agents): set priority/domain directly, unchanged.
      title = args[:title].to_s.strip
      body = "One line of context / acceptance criteria."
      priority = (args[:priority] || ENV["PRIORITY"] || "P1").to_s
      domain = (args[:domain] || ENV["DOMAIN"] || "Ops").to_s
    end

    id = Store.slug_for(title)
    Store.write(
      id: id, body: body.to_s.strip,
      meta: { "id" => id, "title" => title, "priority" => priority, "status" => "open",
              "domain" => domain, "created" => Date.today.iso8601 }
    )
    Rake::Task["tasks:index"].invoke
    puts "Created tasks/#{id}.md#{" (needs triage)" if priority == UNTRIAGED}"
  end

  desc "Triage an untriaged task: rake tasks:triage[id,priority,domain]"
  task :triage, %i[id priority domain] do |_t, args|
    id = (args[:id] || ENV["ID"]).to_s.strip
    priority = (args[:priority] || ENV["PRIORITY"]).to_s.strip
    domain = (args[:domain] || ENV["DOMAIN"]).to_s.strip
    abort "Usage: rake tasks:triage[id,P1,Eng]" if id.empty? || priority.empty? || domain.empty?

    task = Store.find(id)
    task[:meta]["priority"] = priority
    task[:meta]["domain"] = domain
    task[:meta]["updated"] = Date.today.iso8601
    Store.write(id: id, meta: task[:meta], body: task[:body])
    Rake::Task["tasks:index"].invoke
    puts "Triaged #{id} -> #{priority} / #{domain}."
  end

  desc "Claim a task (status: wip): rake tasks:claim[id]"
  task :claim, [ :id ] do |_t, args|
    id = (args[:id] || ENV["ID"]).to_s.strip
    abort "Usage: rake tasks:claim[id]" if id.empty?
    task = Store.find(id)
    task[:meta]["status"] = "wip"
    task[:meta]["updated"] = Date.today.iso8601
    Store.write(id: id, meta: task[:meta], body: task[:body])
    Rake::Task["tasks:index"].invoke
    puts "Claimed #{id}."
  end

  desc "Mark a task done: rake tasks:done[id]"
  task :done, [ :id ] do |_t, args|
    id = (args[:id] || ENV["ID"]).to_s.strip
    abort "Usage: rake tasks:done[id]" if id.empty?
    task = Store.find(id)
    task[:meta]["status"] = "done"
    task[:meta]["updated"] = Date.today.iso8601
    task[:meta].delete("blocked_on")
    Store.write(id: id, meta: task[:meta], body: task[:body])
    Rake::Task["tasks:index"].invoke
    puts "Marked #{id} done."
  end
end

# Top-level convenience alias: `rake task` == `rake tasks:new` with no args
# (opens the git-commit-style editor). Lives outside the namespace so it's a
# bare verb you can muscle-memory.
desc "Create a backlog task in your $EDITOR (git-commit style): rake task"
task :task do
  Rake::Task["tasks:new"].invoke
end
