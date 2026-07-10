# The portfolio registry + the new-venture scaffold. This is what makes holdco a
# *meta*-manager: one file per business under `ventures/` (same one-file-per-entry
# pattern as tasks/), a generated `PORTFOLIO.md` index, and `rake ventures:new`
# which stamps a complete, self-running operator repo into ~/code from
# templates/new-venture/ — so starting business N+1 is one command, not a rebuild.
#
# Venture frontmatter (see ventures/_template.md):
#   id        stable slug (also the filename and default operator command)
#   title     display name
#   tagline   one-line what-it-is
#   repo      path to the venture's own repo
#   operator  the launcher/persona command inside that repo (default: id)
#   status    incubating | idea | building | launching | live | paused | shuttered | killed
#   mode      cadence: long-loop (self-paced /loop — default) | cold (reactive: woken by
#             `bin/holdco nudge` + email, only self-wake is a long COLD_FALLBACK_EVERY loop) |
#             cron (event-driven off its own crons). Drives who holdco nudges. See docs/COST.md.
#   url       live URL (optional)
#   created   YYYY-MM-DD   ·   updated YYYY-MM-DD (optional)

require "yaml"
require "date"
require "fileutils"
require "json"
require "shellwords"

namespace :ventures do
  VENTURES_DIR = "ventures".freeze
  PORTFOLIO_FILE = "PORTFOLIO.md".freeze
  PORTFOLIO_HEADER = "lib/tasks/templates/portfolio_header.md".freeze
  TEMPLATE_DIR = "templates/new-venture".freeze
  # Absolute path to this holdco checkout (location-independent — derived from this
  # rake file, not from cwd). Scaffolded ventures + their operators resolve holdco's
  # tooling and secrets via this, exported as $HOLDCO_ROOT.
  HOLDCO_ROOT = File.expand_path("../..", __dir__).freeze
  # Where new venture repos are created. Default: holdco's parent dir (ventures are
  # SIBLINGS of holdco). Override with VENTURES_ROOT; existing ventures may live
  # anywhere — their path is recorded per-venture in ventures/<id>.md (repo:).
  VENTURES_ROOT = ENV.fetch("VENTURES_ROOT", File.dirname(HOLDCO_ROOT)).freeze
  # True when the caller set VENTURES_ROOT explicitly (e.g. a scaffold smoke-test).
  # In that mode ventures:new skips the real registry write so no phantom venture leaks in.
  VENTURES_ROOT_OVERRIDE = ENV.key?("VENTURES_ROOT").freeze

  # Render order for the portfolio index, with the headings each status gets.
  STATUSES = %w[incubating building launching live idea paused shuttered killed].freeze
  STATUS_HEADING = {
    "incubating" => "🌱 Incubating", "idea" => "💡 Ideas", "building" => "🔨 Building",
    "launching" => "🚀 Launching", "live" => "✅ Live", "paused" => "⏸️ Paused",
    "shuttered" => "🔒 Shuttered", "killed" => "🪦 Killed"
  }.freeze

  module VStore
    module_function

    def files
      Dir.glob(File.join(VENTURES_DIR, "*.md")).reject { |p| File.basename(p).start_with?("_") }.sort
    end

    def all = files.map { |p| read(p) }

    def read(path)
      raw = File.read(path)
      _, fm, body = raw.start_with?("---\n") ? raw.split(/^---\n/, 3) : [ nil, "", raw ]
      meta = (YAML.safe_load(fm, permitted_classes: [ Date ]) || {})
             .transform_keys(&:to_s).transform_values { |v| v.is_a?(Date) ? v.iso8601 : v }
      { meta: meta, body: body.to_s.strip, path: path }
    end

    def write(id:, meta:, body:)
      FileUtils.mkdir_p(VENTURES_DIR)
      order = %w[id title tagline repo operator status mode url created updated]
      fm = {}
      order.each { |k| fm[k] = meta[k] unless meta[k].nil? || meta[k] == "" }
      meta.each { |k, v| fm[k] = v unless order.include?(k) || v.nil? || v == "" }
      path = File.join(VENTURES_DIR, "#{id}.md")
      File.write(path, "#{YAML.dump(fm)}---\n\n#{body.strip}\n")
      path
    end

    def find(id)
      path = File.join(VENTURES_DIR, "#{id}.md")
      raise "No venture #{id.inspect} (looked for #{path})" unless File.exist?(path)

      read(path)
    end
  end

  def slugify(text) = text.to_s.downcase.gsub(/[^a-z0-9_]+/, "-").gsub(/\A-+|-+\z/, "")

  # Rake's `task[a,b]` syntax keeps any inner quotes literally, so a title passed
  # as `["My Title"]` arrives wrapped in quotes. Strip one matching surrounding pair.
  def unquote(text) = text.to_s.strip.sub(/\A(["'])(.*)\1\z/m, '\2').strip

  # ---- ventures:index --------------------------------------------------------

  desc "Regenerate PORTFOLIO.md from the venture files under ventures/"
  task :index do
    ventures = VStore.all
    out = +File.read(PORTFOLIO_HEADER)
    out << "\n" unless out.end_with?("\n\n")

    by_status = ventures.group_by { |v| v[:meta]["status"] }
    STATUSES.each do |status|
      group = (by_status[status] || []).sort_by { |v| v[:meta]["id"].to_s }
      next if group.empty?

      out << "## #{STATUS_HEADING.fetch(status, status)}\n\n"
      group.each do |v|
        m = v[:meta]
        line = +"- **#{m['title']}**"
        line << " — #{m['tagline']}" if m["tagline"].to_s != ""
        out << line << "\n"
        bits = []
        bits << "[#{m['url']}](#{m['url']})" if m["url"].to_s != ""
        bits << "`#{m['repo']}`" if m["repo"].to_s != ""
        bits << "run: `./#{m['operator'] || m['id']}`"
        out << "  - #{bits.join('  ·  ')}\n"
        first = v[:body].to_s.lines.first.to_s.strip
        out << "  - #{first}\n" unless first.empty?
      end
      out << "\n"
    end

    File.write(PORTFOLIO_FILE, out)
    puts "Wrote #{PORTFOLIO_FILE} from #{ventures.size} venture(s)."
  end

  desc "List ventures (id · status · repo)"
  task :list do
    VStore.all.each do |v|
      m = v[:meta]
      puts format("%-20s %-10s %s", m["id"], m["status"], m["repo"])
    end
  end

  # ---- driving operators (tmux windows + claude --remote-control) -----------
  # Each venture's operator runs as a named tmux window in the owner's session,
  # launched with `claude --remote-control` so the owner can chat from claude.ai/code.
  # See docs/ORCHESTRATION.md.

  # Locate a venture's operator persona file. Scaffolded repos use operator.md;
  # an existing venture may name it after its operator command.
  def operator_persona(repo, operator)
    [ ".claude/agents/#{operator}.md", ".claude/agents/operator.md" ]
      .find { |rel| File.exist?(File.join(repo, rel)) }
  end

  # All tmux window names in the target session (operator windows are named after
  # the first word of the venture title, e.g. "Acme"). Used for idempotency + fleet matching.
  def tmux_window_names(session)
    raw = `tmux list-windows -t #{session.shellescape} -F '\#{window_name}' 2>/dev/null`
    raw.split("\n").map(&:strip).reject(&:empty?)
  rescue
    []
  end

  # A venture window's tmux colour. Frontmatter `color:` wins; otherwise derive a
  # STABLE colour from the venture id via a hash into the ANSI palette.
  #
  # Primary palette: ANSI theme-colour names (adapt to the user's terminal theme).
  # Avoids black/white. Picked by stable hash of the venture id.
  ANSI_PALETTE = %w[
    red green yellow blue magenta cyan
    brightred brightgreen brightyellow brightblue brightmagenta brightcyan
  ].freeze

  # 256-colour overflow fallback — appended to extend the effective palette when
  # venture count exceeds ANSI_PALETTE.size (12). Stays unused until needed.
  COLOUR256_FALLBACK = %w[
    colour203 colour214 colour220 colour135 colour45 colour171 colour111 colour208
  ].freeze

  def window_color(id, meta)
    c = meta["color"].to_s.strip
    return c unless c.empty?
    # ANSI slots fill first; 256-colour slots absorb overflow for fleets > 12.
    palette = ANSI_PALETTE + COLOUR256_FALLBACK
    palette[id.bytes.sum % palette.size]
  end

  # tmux commands that pin the window name (no auto-rename) and colour its status entry.
  # The window-status-format pair drops the cwd prefix from the owner's GLOBAL format
  # (cwd is redundant for an operator tab) — a per-window override only, so ~/.tmux.conf
  # is untouched. Single-quoted: the #{...} is tmux format syntax, not Ruby interpolation.
  CLEAN_STATUS_FORMAT = ' #W#{?window_bell_flag, !,} '
  def window_style_cmds(target, window, color)
    t = "#{target}:#{window}"
    [
      [ "tmux", "set-window-option", "-t", t, "automatic-rename", "off" ],
      [ "tmux", "set-window-option", "-t", t, "window-status-format", CLEAN_STATUS_FORMAT ],
      [ "tmux", "set-window-option", "-t", t, "window-status-current-format", CLEAN_STATUS_FORMAT ],
      [ "tmux", "set-window-option", "-t", t, "window-status-style", "fg=#{color}" ],
      [ "tmux", "set-window-option", "-t", t, "window-status-current-style", "fg=#{color},reverse" ]
    ]
  end

  desc "Dispatch a venture operator as a named tmux window (claude --remote-control): " \
       "rake ventures:run[id]   (GOAL=… to set the task; DRY_RUN=1 or HOLDCO_DEBUG=1 to preview)"
  task :run, [ :id ] do |_t, args|
    id = slugify(args[:id] || ENV["ID"])
    abort "Usage: rake ventures:run[id]   (GOAL=… optional)" if id.empty?
    v = VStore.find(id)
    repo = File.expand_path(v[:meta]["repo"].to_s)
    abort "Venture repo not found: #{repo}" unless File.directory?(repo)
    persona = operator_persona(repo, v[:meta]["operator"] || id)
    abort "No operator persona under #{repo}/.claude/agents/ (operator.md or #{v[:meta]['operator']}.md)" unless persona

    title  = v[:meta]["title"] || id
    window = title.split.first        # first word of title as the tmux tab name (e.g. "Acme")
    remote = "#{title} Operator"      # long --remote-control conversation name
    # This operator's own email-channel inbox (matches bin/holdco operator_address +
    # the Email Routing rules: one rule per operator, <id>@<FLEET_EMAIL_DOMAIN> → inbox Worker).
    fleet_domain = ENV["FLEET_EMAIL_DOMAIN"].to_s.strip
    fleet_domain = "bot.example.com" if fleet_domain.empty?
    addr   = "#{window.downcase}@#{fleet_domain}"
    goal = ENV["GOAL"].to_s.strip
    if goal.empty?
      goal = if v[:meta]["status"] == "incubating"
        "This venture is in INCUBATION. Your only job right now is to write BUSINESS-PLAN.md — " \
        "research the thesis, market, competition, business model, unit economics, MVP scope, and risks. " \
        "Fill every section with specific, honest analysis. When complete, log it and STOP — " \
        "await holdco's greenlight before building anything."
      else
        "Continue #{title} operation."
      end
    end
    # Cadence mode (frontmatter `mode`) sets the launch driver. `cold` operators run
    # NO frequent self-loop — their only self-wake is a long fallback interval (6–12h)
    # so a missed holdco nudge can never strand them; normal cadence comes from
    # `bin/holdco nudge` + inbound email waking the idle prompt sooner. `long-loop`
    # (default) and `cron` keep the legacy self-paced /loop. See docs/COST.md.
    mode = (v[:meta]["mode"].to_s.strip.empty? ? "long-loop" : v[:meta]["mode"].to_s.strip)
    goal = if mode == "cold"
      "/loop #{ENV.fetch('COLD_FALLBACK_EVERY', '8h')} /clear #{goal}"
    else
      "/loop /clear #{goal}"
    end
    model  = ENV["OP_MODEL"] || "sonnet"
    target = ENV.fetch("HOLDCO_TMUX_SESSION", "holdco")
    color  = window_color(id, v[:meta])
    persona_path = File.join(repo, persona)

    # --channels enables the in-session email channel. It only renders if the venture's
    # OWN repo .claude/settings.json also carries {"enabledPlugins":{"email@holdco-fleet":true}}
    # (gate 2 — added by the template for new ventures, or at each existing venture's cutover)
    # AND the channel server gets EMAIL_CHANNEL_ADDR (passed via tmux -e below). See docs/CHANNELS.md.
    claude_argv = [
      "claude", "--remote-control", remote,
      "--model", model, "--effort", "high", "--dangerously-skip-permissions",
      "--channels", "plugin:email@holdco-fleet",
      "--append-system-prompt-file", persona_path, goal
    ]

    # Supervise the operator under holdco's bin/operator-loop so its claude process
    # is recycled before its RSS can balloon and OOM the box (see bin/operator-loop).
    # holdco is the sole supervisor, so the wrapper lives here and is referenced by
    # absolute path — this works for non-scaffolded ventures too. Escape: OPERATOR_NO_LOOP=1.
    wrapper     = File.expand_path("bin/operator-loop")
    window_argv = if ENV["OPERATOR_NO_LOOP"] == "1" || !File.executable?(wrapper)
      claude_argv
    else
      [ wrapper, *claude_argv.drop(1) ]   # wrapper re-prepends `claude`
    end
    # -d: create the window in the background so dispatching an operator never
    # steals the owner's current view (no active-window switch as a side effect).
    # -e binds the operator's email-channel inbox into the launched process env; it
    # flows through bin/operator-loop (inherits env) to the claude/channel MCP server.
    # HOLDCO_ROOT lets the operator resolve holdco tooling ($HOLDCO_ROOT/bin/email etc.)
    # regardless of where holdco or the venture live.
    tmux_prefix = [ "tmux", "new-window", "-d",
                    "-e", "EMAIL_CHANNEL_ADDR=#{addr}", "-e", "HOLDCO_ROOT=#{HOLDCO_ROOT}",
                    "-t", target, "-n", window, "-c", repo ]
    style_cmds  = window_style_cmds(target, window, color)

    if ENV["DRY_RUN"] == "1" || ENV["HOLDCO_DEBUG"] == "1"
      puts "[dry-run] #{tmux_prefix.shelljoin} #{window_argv.shelljoin}"
      style_cmds.each { |c| puts "[dry-run] #{c.shelljoin}" }
      next
    end

    # Ensure the target tmux session exists (creates detached if missing, e.g. @reboot).
    unless system("tmux has-session -t #{target.shellescape} 2>/dev/null")
      system("tmux", "new-session", "-d", "-s", target) || abort("Failed to create tmux session '#{target}'")
      puts "Created tmux session '#{target}' (detached)."
    end

    # Idempotent: no-op if the window (by tab name = first word of title) is already running.
    if tmux_window_names(target).include?(window)
      puts "#{id}: window '#{window}' already open in tmux:#{target} — no-op"
      next
    end

    puts "Dispatching #{id} operator → tmux:#{target} window '#{window}' (#{color}) …"
    system(*tmux_prefix, window_argv.shelljoin) || abort("dispatch failed")
    style_cmds.each { |c| system(*c) } # pin name + colour the window's status entry
    puts "Steer: tmux attach -t #{target}  |  claude.ai/code"
  end

  desc "Show running operator sessions per venture (tmux windows + claude agents --json)"
  task :fleet do
    session = ENV.fetch("HOLDCO_TMUX_SESSION", "holdco")
    wins    = tmux_window_names(session)
    out     = `claude agents --json --all 2>/dev/null`
    agents  = (JSON.parse(out) rescue [])
    by_repo = agents.group_by { |a| File.expand_path(a["cwd"].to_s) }
    VStore.all.each do |v|
      id     = v[:meta]["id"]
      tab    = (v[:meta]["title"] || id).to_s.split.first   # tab name = first word of title
      repo   = File.expand_path(v[:meta]["repo"].to_s)
      mine   = (by_repo[repo] || []).reject { |a| a["state"] == "done" && a["kind"] == "background" }
      mode   = (v[:meta]["mode"].to_s.strip.empty? ? "long-loop" : v[:meta]["mode"].to_s.strip)
      if wins.include?(tab)
        puts format("%-20s  tmux:%-4s %-10s %s", id, session, mode, "#{v[:meta]['title']} Operator")
      elsif mine.empty?
        puts format("%-20s  —  %-10s (no active session)", v[:meta]["id"], mode)
      else
        mine.each do |a|
          tag = a["id"] || a["sessionId"].to_s[0, 8]
          puts format("%-20s  %-10s %-8s %-7s %-10s %s", v[:meta]["id"], a["kind"], a["status"], a["state"] || "", mode, tag)
        end
      end
    end
  end

  desc "Register an EXISTING repo as a venture without scaffolding: " \
       "rake ventures:register[id,Title,repo,operator]"
  task :register, %i[id title repo operator] do |_t, args|
    id = slugify(args[:id] || ENV["ID"])
    abort "Usage: rake ventures:register[id,Title,/path/to/repo,operatorcmd]" if id.empty?
    VStore.write(
      id: id,
      meta: { "id" => id, "title" => unquote(args[:title] || ENV["TITLE"] || id),
              "repo" => (args[:repo] || ENV["REPO"]).to_s,
              "operator" => (args[:operator] || ENV["OPERATOR"] || id),
              "status" => (ENV["STATUS"] || "building"),
              "tagline" => unquote(ENV["TAGLINE"]), "url" => ENV["URL"].to_s,
              "created" => Date.today.iso8601 },
      body: ENV["NOTE"].to_s.strip.empty? ? "Registered existing repo." : ENV["NOTE"]
    )
    Rake::Task["ventures:index"].invoke
    puts "Registered venture #{id}."
  end

  # ---- ventures:new (the scaffold) ------------------------------------------

  PLACEHOLDER_FILES_SKIP = %w[.git].freeze

  desc "Scaffold a new operator repo from templates/new-venture and register it: " \
       "rake 'ventures:new[name,Display Title,one-line tagline]'"
  task :new, %i[name title tagline] do |_t, args|
    name = slugify(args[:name] || ENV["NAME"])
    abort "Usage: rake 'ventures:new[name,Display Title,one-line tagline]'" if name.empty?
    title = unquote(args[:title] || ENV["TITLE"] || name)
    tagline = unquote(args[:tagline] || ENV["TAGLINE"] || "")
    today = Date.today.iso8601

    # Ventures can live ANYWHERE. Default: a sibling of holdco (VENTURES_ROOT/name).
    # Override the location for THIS venture with VENTURE_PATH=/abs/path (the stored
    # `repo:` path is what every fleet tool resolves by — not a fixed root).
    dest = ENV["VENTURE_PATH"].to_s.strip.empty? ? File.join(VENTURES_ROOT, name) : File.expand_path(ENV["VENTURE_PATH"])
    abort "Refusing: #{dest} already exists." if File.exist?(dest)
    abort "Missing template dir #{TEMPLATE_DIR}." unless File.directory?(TEMPLATE_DIR)

    subs = { "{{VENTURE}}" => name, "{{TITLE}}" => title,
             "{{TAGLINE}}" => tagline, "{{DATE}}" => today }

    # Copy the template tree, substituting placeholders in every text file.
    Dir.glob(File.join(TEMPLATE_DIR, "**", "*"), File::FNM_DOTMATCH).each do |src|
      rel = src.delete_prefix("#{TEMPLATE_DIR}/")
      next if rel == "." || rel.split(File::SEPARATOR).first&.then { |top| PLACEHOLDER_FILES_SKIP.include?(top) }

      out = File.join(dest, rel)
      if File.directory?(src)
        FileUtils.mkdir_p(out)
      else
        content = File.read(src)
        subs.each { |k, v| content = content.gsub(k, v) }
        FileUtils.mkdir_p(File.dirname(out))
        File.write(out, content)
        FileUtils.chmod(File.stat(src).mode, out)
      end
    end

    # Rename the generic launcher script to the venture command (`./<name>`).
    launcher = File.join(dest, "operator")
    if File.exist?(launcher)
      FileUtils.mv(launcher, File.join(dest, name))
      FileUtils.chmod(0o755, File.join(dest, name))
    end

    # Seed the venture's machine-local .env (gitignored) with HOLDCO_ROOT so the
    # operator's shell resolves holdco tooling/secrets via $HOLDCO_ROOT — both when
    # launched by holdco (ventures:run passes -e HOLDCO_ROOT) and when run directly
    # via ./#{name} (the launcher sources this .env). Add tasks/email tokens here later.
    File.write(File.join(dest, ".env"), <<~ENV)
      # Machine-local env for this venture's operator — gitignored, never committed.
      # HOLDCO_ROOT: absolute path to the holdco checkout that scaffolded this venture.
      # Operators resolve holdco tooling ($HOLDCO_ROOT/bin/email, /bin/holdco) + secrets via it.
      HOLDCO_ROOT=#{HOLDCO_ROOT}
    ENV

    # CLAUDE.md -> AGENTS.md symlink (matches the established convention).
    Dir.chdir(dest) do
      FileUtils.ln_s("./AGENTS.md", "CLAUDE.md") if File.exist?("AGENTS.md") && !File.exist?("CLAUDE.md")
      sh_quiet("git init -q")
      Rake.rake_output_message("Initialized git in #{dest}")
      # Seed TASKS.md so the backlog index exists from day one.
      sh_quiet("rake tasks:index") if File.exist?("Rakefile")
      sh_quiet("git add -A && git commit -q -m 'Scaffold #{title} operator repo from holdco template'")
    end

    # Register in the portfolio — skipped when VENTURES_ROOT is overridden (e.g. a
    # scaffold smoke-test via `VENTURES_ROOT=$(mktemp -d) bin/holdco new ...`), so
    # the real ventures/ directory is never touched during an isolated scaffold check.
    if VENTURES_ROOT_OVERRIDE
      puts <<~MSG

        Scaffolded #{title} at #{dest}
           (VENTURES_ROOT override — skipping registry write; real ventures/ is untouched)
           Repo is ready but NOT registered in the portfolio.

      MSG
    else
      VStore.write(
        id: name,
        meta: { "id" => name, "title" => title, "tagline" => tagline, "repo" => dest,
                "operator" => name, "status" => "incubating", "created" => today },
        body: "Scaffolded #{today} from holdco templates/new-venture. " \
               "Status: INCUBATING — operator writes BUSINESS-PLAN.md before building. " \
               "Next: cd #{dest} && ./#{name}"
      )
      Rake::Task["ventures:index"].invoke

      puts <<~MSG

        Scaffolded #{title} at #{dest}
           registered in ventures/#{name}.md and PORTFOLIO.md (status: incubating)

        Incubation flow:
           1. cd #{dest}
           2. ./#{name}              # operator writes BUSINESS-PLAN.md — thesis/market/model/MVP/risks
           3. holdco reviews         # bin/holdco run #{name} or read BUSINESS-PLAN.md directly
           4. greenlight → edit ventures/#{name}.md status to 'building', bin/holdco index
              OR shutter → bin/holdco shutter #{name}
      MSG
    end
  end

  # ---- ventures:shutter -------------------------------------------------------

  desc "Gracefully shutter a venture: stop its operator tmux window, set status to " \
       "'shuttered', append a postmortem stub, regenerate index. Repo is preserved."
  task :shutter, [:id] do |_t, args|
    id = slugify(args[:id] || ENV["ID"])
    abort "Usage: rake ventures:shutter[id]" if id.empty?

    v      = VStore.find(id)
    meta   = v[:meta]
    body   = v[:body]
    title  = meta["title"] || id
    today  = Date.today.iso8601

    # Kill tmux window if running (same window-name logic as :run).
    window = title.split.first
    target = ENV.fetch("HOLDCO_TMUX_SESSION", "holdco")
    if tmux_window_names(target).include?(window)
      system("tmux", "kill-window", "-t", "#{target}:#{window}")
      puts "#{id}: stopped operator window '#{window}' in tmux:#{target}."
    else
      puts "#{id}: no operator window '#{window}' running — nothing to stop."
    end
    # SIGTERM any surviving claude/node processes in the venture's repo CWD.
    # The --remote-control daemon can detach (setsid) and outlive the window kill.
    # (bin/holdco shutter routes through bin/holdco stop first, so these are usually
    # already gone — this is the safety net when ventures:shutter is called directly.)
    repo_abs = File.expand_path(meta["repo"].to_s)
    orphans = Dir.glob("/proc/[0-9]*/cwd").filter_map do |cwd_link|
      link = File.readlink(cwd_link) rescue nil
      next unless link == repo_abs
      pid = cwd_link[%r{/proc/(\d+)/cwd}, 1].to_i
      next if pid == 0 || pid == Process.pid
      comm = File.read("/proc/#{pid}/comm").strip rescue ""
      pid if comm == "claude" || comm == "node"
    end rescue []
    orphans.each { |pid| Process.kill("TERM", pid) rescue nil }
    puts "#{id}: SIGTERMed #{orphans.length} orphan process(es): #{orphans.join(', ')}." if orphans.any?

    # Mark shuttered and append a postmortem stub.
    meta["status"]  = "shuttered"
    meta["updated"] = today
    postmortem = <<~PM

      ## Postmortem — #{today}

      **Why shuttered:** <!-- what failed to validate, or what would have been needed -->

      **What we learned:** <!-- key lessons for future ventures -->

      **Could be revived if:** <!-- optional: conditions worth revisiting -->
    PM
    new_body = body.strip.empty? ? postmortem.lstrip : "#{body.strip}\n#{postmortem}"

    VStore.write(id: id, meta: meta, body: new_body)
    Rake::Task["ventures:index"].invoke
    puts "#{id}: shuttered. Repo at #{meta['repo']} preserved (archived in place)."
  end

  # Run a shell command from the current dir, raising on failure. Kept tiny so the
  # scaffold reads top-to-bottom; `sh` would echo every command.
  def sh_quiet(cmd)
    system(cmd) || raise("command failed: #{cmd}")
  end
end
