#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "erb"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "optparse"
require "pathname"
require "time"
require "uri"
require "yaml"

begin
  require "bibtex"
rescue LoadError
  warn "Missing bibtex-ruby. Try: bundle exec ruby cv/generate_cv.rb"
  exit 1
end

module CvLatex
  module_function

  CJK_PATTERN = /[\p{Han}\p{Hiragana}\p{Katakana}]/
  LATEX_REPLACEMENTS = {
    "\\" => "\\textbackslash{}",
    "{" => "\\{",
    "}" => "\\}",
    "$" => "\\$",
    "&" => "\\&",
    "#" => "\\#",
    "_" => "\\_",
    "%" => "\\%",
    "~" => "\\textasciitilde{}",
    "^" => "\\textasciicircum{}"
  }.freeze

  def normalize_unicode(text, strip: true)
    normalized = text.to_s
                     .tr("“”„", '"')
                     .tr("‘’`", "'")
                     .gsub("–", "--")
                     .gsub("—", "--")
                     .gsub("−", "-")
                     .gsub("→", "->")
                     .gsub("‹", "")
                     .gsub("›", "")
                     .gsub("λ", "lambda")
                     .gsub("∀", "forall")
                     .gsub(/[[:space:]]+/, " ")
    strip ? normalized.strip : normalized
  end

  def strip_markup(value, drop_spans: false, keep_link_labels: true)
    text = value.to_s.dup
    text.gsub!(/<!--.*?-->/m, " ")
    text.gsub!(/<span\b[^>]*>.*?<\/span>/mi) do |span|
      drop_spans || span.match?(CJK_PATTERN) ? " " : span.gsub(/<\/?span\b[^>]*>/i, " ")
    end
    if keep_link_labels
      text.gsub!(/<a\b[^>]*>(.*?)<\/a>/mi) { Regexp.last_match(1) }
      text.gsub!(/\[([^\]]+)\]\([^)]+\)/, "\\1")
    end
    text.gsub!(/<br\s*\/?>/i, " ")
    text.gsub!(/<\/?(?:b|i|em|strong|u)\b[^>]*>/i, "")
    text.gsub!(/<[^>]+>/, " ")
    text = CGI.unescapeHTML(text).gsub("&nbsp;", " ")
    text.gsub!(/[👉]/, "")
    text.gsub!(/[※]/, "")
    text.gsub!(/\([^)]*#{CJK_PATTERN.source}[^)]*\)/, " ")
    text.gsub!(/（[^）]*#{CJK_PATTERN.source}[^）]*）/, " ")
    text.gsub!(/\(\s*\)/, " ")
    text.gsub!(/\s+\)/, "")
    text
  end

  def plain(value, drop_spans: false)
    normalize_unicode(strip_markup(value, drop_spans: drop_spans))
  end

  def latex(value)
    plain(value).gsub(/[\\{}$&#_%~^]/) { |char| LATEX_REPLACEMENTS.fetch(char) }
  end

  def latex_with_links(value, drop_spans: false)
    text = value.to_s.dup
    links = {}

    text.gsub!(/<a\b([^>]*)>(.*?)<\/a>/mi) do
      attrs = Regexp.last_match(1)
      label = Regexp.last_match(2)
      href = attrs[/\bhref\s*=\s*(["'])(.*?)\1/i, 2]
      token = "CVLATEXLINK#{links.length}CVLATEXLINK"
      links[token] = link(href, plain(label, drop_spans: drop_spans))
      token
    end

    text.gsub!(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) do
      label = Regexp.last_match(1)
      href = Regexp.last_match(2)
      token = "CVLATEXLINK#{links.length}CVLATEXLINK"
      links[token] = link(href, plain(label, drop_spans: drop_spans))
      token
    end

    text = normalize_unicode(strip_markup(text, drop_spans: drop_spans, keep_link_labels: false))
    text.split(/(CVLATEXLINK\d+CVLATEXLINK)/).map do |part|
      links.fetch(part) { latex_raw_plain(part, strip: false) }
    end.join
  end

  def latex_raw_plain(value, strip: true)
    normalize_unicode(value, strip: strip).gsub(/[\\{}$&#_%~^]/) { |char| LATEX_REPLACEMENTS.fetch(char) }
  end

  def url(value)
    value.to_s.strip.gsub("\\", "/").gsub(" ", "%20")
  end

  def href_url(value)
    CGI.unescapeHTML(url(value)).gsub(/[\\{}%#&_]/) do |char|
      {
        "\\" => "\\textbackslash{}",
        "{" => "\\{",
        "}" => "\\}",
        "%" => "\\%",
        "#" => "\\#",
        "&" => "\\&",
        "_" => "\\_"
      }.fetch(char)
    end
  end

  def link(href, label)
    clean_href = href.to_s.strip
    clean_label = plain(label)
    return latex_raw_plain(clean_label) if clean_href.empty? || clean_label.empty?

    "\\href{#{href_url(clean_href)}}{#{latex_raw_plain(clean_label)}}"
  end
end

class CvGenerator
  ROOT = File.expand_path("..", __dir__)
  CV_DIR = __dir__
  RESEARCHMAP_BASE_URL = "https://api.researchmap.jp"
  MONTHS = {
    "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4, "may" => 5, "jun" => 6,
    "jul" => 7, "aug" => 8, "sep" => 9, "oct" => 10, "nov" => 11, "dec" => 12
  }.freeze
  MONTH_LABELS = %w[Jan. Feb. Mar. Apr. May Jun. Jul. Aug. Sep. Oct. Nov. Dec.].freeze

  def initialize(options)
    @options = options
    @build_dir = File.expand_path(options[:build_dir], ROOT)
    @researchmap_cache = File.expand_path(
      options[:researchmap_cache] || File.join("cv", "cache", "researchmap_presentations_#{options[:researchmap_id]}.json"),
      ROOT
    )
  end

  def run
    FileUtils.mkdir_p(@build_dir)
    cv = build_cv
    tex_path = File.join(@build_dir, "CV.tex")
    template = ERB.new(File.read(File.join(CV_DIR, "template.tex.erb")), trim_mode: "-")
    File.write(tex_path, template.result_with_hash(cv: cv, helper: CvLatex))

    return puts("wrote #{relative(tex_path)}") if @options[:no_pdf]

    compile_pdf(tex_path)
    puts("wrote #{relative(File.join(@build_dir, "CV.pdf"))}")
  end

  private

  def path(relative_path)
    File.join(ROOT, relative_path)
  end

  def relative(absolute_path)
    Pathname.new(absolute_path).relative_path_from(Pathname.new(ROOT)).to_s
  end

  def yaml(relative_path)
    YAML.load_file(path(relative_path)) || []
  end

  def front_matter(relative_path)
    text = File.read(path(relative_path))
    return [{}, text] unless text.match?(/\A---\s*\n/)

    match = text.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    return [{}, text] unless match

    [YAML.safe_load(match[1], aliases: true) || {}, match.post_match]
  end

  def build_cv
    config = yaml("_config.yml")
    about_fm, about_body = front_matter("_pages/about.md")
    cv_data = yaml("_data/cv.yml")

    profile_image = File.join("assets", "img", about_fm.dig("profile", "image") || "profile_img.jpg")
    image_path = path(profile_image)
    image_tex_path = if File.exist?(image_path)
                       Pathname.new(image_path).relative_path_from(Pathname.new(@build_dir)).to_s
                     end

    sections = []
    sections << section_from_time_table("Education", find_section(cv_data, "Education"))
    sections.concat(grant_sections)
    sections << section_from_time_table("Fellowships", find_section(cv_data, "Scholarship"))
    sections << section_from_time_table("Job Experience", find_section(cv_data, "Job Experience"))
    sections.concat(teaching_sections)
    sections << publications_section
    edited = edited_proceedings_section
    sections << edited if edited[:entries].any?
    invited = invited_talks_section
    sections << invited if invited[:entries].any?
    sections << academic_service_section

    sections.compact!
    sections.reject! { |section| Array(section[:entries]).empty? && Array(section[:groups]).empty? }

    {
      name: [config["first_name"], config["middle_name"], config["last_name"]].compact.reject(&:empty?).join(" "),
      email: extract_email(about_body),
      website: config["url"] || "https://yudaitnb.github.io",
      profile_image_tex: image_tex_path,
      statement: statement(about_body),
      research: research(about_body),
      generated_on: Time.now.strftime("%Y-%m-%d"),
      sections: sections
    }
  end

  def find_section(data, title)
    data.find { |entry| CvLatex.plain(entry["title"]).casecmp(title).zero? }
  end

  def section_from_time_table(title, section)
    return nil unless section

    entries = Array(section["contents"]).map { |item| time_table_entry(item) }
    if title == "Education"
      entries.each do |entry|
        next unless entry[:title] == "Doctor of Science"

        entry[:bullets] = []
        entry[:bullets_tex] = []
      end
    elsif title == "Job Experience"
      entries.each do |entry|
        entry[:bullets] = []
        entry[:bullets_tex] = []
      end
    end

    {
      title: title,
      entries: entries
    }
  end

  def time_table_entry(item)
    {
      title: clean_data_text(item["title"]),
      title_tex: clean_data_tex(item["title"]),
      date: normalize_date(item["year"]),
      subtitle: clean_data_text(item["institution"]),
      subtitle_tex: clean_data_tex(item["institution"]),
      meta: clean_data_text(item["location"]),
      meta_tex: clean_data_tex(item["location"]),
      bullets: descriptions(item["description"]),
      bullets_tex: descriptions_tex(item["description"])
    }
  end

  def grant_sections
    yaml("_data/grants.yml").filter_map do |section|
      title = case CvLatex.plain(section["title"])
              when /Principal Investigator/i then "Grants"
              when /Co-investigator/i then "Grants (Co-investigator)"
              else CvLatex.plain(section["title"])
              end

      entries = Array(section["contents"]).map do |item|
        desc_items = description_items(item["description"])
        project_item = desc_items.find { |line| clean_data_text(line).match?(/Project Number/i) }
        project = clean_data_text(project_item).sub(/\AProject Number\s*/i, "")
        project_tex = clean_data_tex(project_item).sub(/\AProject Number\s*/i, "")
        grant_kind_items = desc_items.reject { |line| clean_data_text(line).match?(/Project Number/i) }
                                    .select { |line| clean_data_text(line).match?(/\AGrant(?:-| )in[- ]Aid/i) }
        subtitle_parts = [clean_data_text(item["institution"]), *grant_kind_items.map { |line| clean_data_text(line) }]
        subtitle_tex_parts = [clean_data_tex(item["institution"]), *grant_kind_items.map { |line| clean_data_tex(line) }]
        {
          title: clean_data_text(item["title"]),
          title_tex: clean_data_tex(item["title"]),
          date: normalize_date(item["year"]),
          subtitle: subtitle_parts.reject(&:empty?).join(", "),
          subtitle_tex: subtitle_tex_parts.reject(&:empty?).join(CvLatex.latex_raw_plain(", ", strip: false)),
          meta: project,
          meta_tex: project_tex,
          bullets: [],
          bullets_tex: []
        }
      end

      { title: title, entries: entries }
    end
  end

  def teaching_sections
    groups = parse_teaching_page
    [
      { title: "Teaching Experience as an Educator", entries: strip_entry_bullets(groups.fetch(:educator)) },
      { title: "Teaching Experience as a TA", entries: strip_entry_bullets(groups.fetch(:ta)) }
    ]
  end

  def strip_entry_bullets(entries)
    entries.map { |entry| entry.merge(bullets: [], bullets_tex: []) }
  end

  def parse_teaching_page
    _fm, body = front_matter("_pages/teaching.md")
    groups = { educator: [], ta: [] }
    current_kind = nil
    current_entry = nil

    body.each_line do |line|
      case line
      when /^## Courses in Latest Academic Year/i, /^## Past Courses/i
        current_kind = :educator
        current_entry = nil
      when /^## Coursework Support/i
        current_kind = :ta
        current_entry = nil
      when /^## /
        current_kind = nil
        current_entry = nil
      when /^##### /
        current_entry = nil
      when /^- <a class="font-weight-bold">(.+?)<\/a>,\s*<span[^>]*>(.*?)<\/span>\.\s*(.*?)\.\s*$/
        next unless current_kind

        current_entry = {
          title: CvLatex.plain(Regexp.last_match(1)),
          role: CvLatex.plain(Regexp.last_match(2)),
          institution: CvLatex.plain(Regexp.last_match(3)),
          items: []
        }
        groups.fetch(current_kind) << current_entry
      when /^\s+-\s+(.+)$/
        next unless current_entry

        raw_item = Regexp.last_match(1)
        item = CvLatex.plain(raw_item)
        current_entry[:items] << { plain: item, tex: CvLatex.latex_with_links(raw_item) } unless item.empty?
      end
    end

    groups.transform_values { |entries| merge_teaching_entries(entries) }
  end

  def merge_teaching_entries(entries)
    merged = {}
    entries.each do |entry|
      key = [entry[:title], entry[:role], entry[:institution]]
      merged[key] ||= entry.merge(items: [])
      merged[key][:items].concat(entry[:items])
    end

    merged.values.map do |entry|
      items = entry[:items].uniq { |item| item[:plain] }
      years = items.flat_map { |item| item[:plain].scan(/\b(20\d{2})\b/).flatten.map(&:to_i) }.uniq.sort
      {
        title: entry[:title],
        date: year_range(years),
        subtitle: entry[:institution],
        meta: entry[:role],
        bullets: items.map { |item| item[:plain] },
        bullets_tex: items.map { |item| item[:tex] }
      }
    end.sort_by { |entry| [-(entry[:date].to_s.scan(/\d{4}/).map(&:to_i).max || 0), entry[:title]] }
  end

  def publications
    BibTeX.open(path("_bibliography/papers.bib")).select do |entry|
      %i[article inproceedings incollection].include?(entry.type)
    end.sort_by { |entry| [-field(entry, :year).to_i, -month_number(field(entry, :month)), field(entry, :title)] }
  end

  def publications_section
    {
      title: "Publications",
      entries: publications.map { |entry| publication_entry(entry) }
    }
  end

  def edited_proceedings_section
    entries = BibTeX.open(path("_bibliography/papers.bib")).select { |entry| entry.type == :book }
                   .sort_by { |entry| [-field(entry, :year).to_i, field(entry, :title)] }
                   .map { |entry| publication_entry(entry, editor: true) }
    { title: "Edited Proceedings", entries: entries }
  end

  def publication_entry(entry, editor: false)
    venue = [field(entry, :journal), field(entry, :booktitle), field(entry, :howpublished), field(entry, :publisher)]
            .find { |value| !value.empty? }
    details = []
    details << "In #{venue}" unless venue.empty?
    details << "Vol. #{field(entry, :volume)}" unless field(entry, :volume).empty?
    details << "No. #{field(entry, :number)}" unless field(entry, :number).empty? || field(entry, :number).strip.empty?
    details << "pp. #{field(entry, :pages)}" unless field(entry, :pages).empty?
    details << "DOI: #{field(entry, :doi)}" unless field(entry, :doi).empty?
    details_tex = publication_details_tex(entry, venue)
    title = clean_bib_text(field(entry, :title))
    link_url = publication_url(entry)

    names = editor ? field(entry, :editor) : field(entry, :author)
    {
      title: title,
      title_tex: link_url.empty? ? CvLatex.latex_raw_plain(title) : CvLatex.link(link_url, title),
      date: field(entry, :year),
      subtitle_tex: authors_tex(names),
      meta: clean_bib_text(field(entry, :abbr)),
      note: clean_bib_text(details.join(", ")),
      note_tex: details_tex,
      bullets: [],
      bullets_tex: []
    }
  end

  def invited_talks_section
    entries = researchmap_presentations.select { |item| item["invited"] == true }
                                        .sort_by { |item| researchmap_sort_date(item) }
                                        .reverse
                                        .map { |item| researchmap_presentation_entry(item) }

    { title: "Invited Talks", entries: entries }
  end

  def academic_service_section
    groups = yaml("_data/activities.yml").map do |section|
      category = CvLatex.plain(section["title"])
      {
        title: category,
        items: Array(section["contents"]).map do |group|
          services = Array(group["items"]).map do |item|
            academic_service_item_tex(item, category)
          end.reject(&:empty?)

          {
            year: normalize_date(group["year"]),
            services_tex: services
          }
        end.reject { |item| item[:services_tex].empty? }
      }
    end
    groups.reject! { |group| group[:items].empty? }

    { title: "Academic Service", groups: groups, entries: [] }
  end

  def academic_service_item_tex(item, _category)
    text = item.to_s.dup
    text.gsub!(/<span\b[^>]*>.*?<\/span>/mi, " ")
    text.sub!(/\s*\(.*\)\s*\z/m, "")
    clean_data_tex(text)
  end

  def descriptions(value)
    description_items(value).map { |item| clean_data_text(item) }.reject(&:empty?)
  end

  def descriptions_tex(value)
    description_items(value).map { |item| clean_data_tex(item) }.reject(&:empty?)
  end

  def description_items(value)
    Array(value).flat_map do |item|
      if item.is_a?(Hash)
        [item["title"], *Array(item["contents"])]
      else
        item
      end
    end
  end

  def statement(body)
    bio = body[/<summary>\s*Short Bio \(en\)\s*<\/summary>\s*(.*?)<\/details>/mi, 1]
    CvLatex.plain(bio || "")
  end

  def research(body)
    block = body[/^## research interests\s*(.*?)(?:\n^## |\z)/mi, 1].to_s
    block.sub!(/<!--.*?\z/m, "")
    lines = block.lines
    projects = lines.select { |line| line.match?(/^\d+\.\s+/) }
                    .map { |line| CvLatex.plain(line.sub(/^\d+\.\s+/, "")) }
                    .reject(&:empty?)
    projects_tex = lines.select { |line| line.match?(/^\d+\.\s+/) }
                        .map { |line| CvLatex.latex_with_links(line.sub(/^\d+\.\s+/, "")) }
                        .reject(&:empty?)

    intro_lines = []
    lines.each do |line|
      break if line.match?(/^\d+\.\s+/)

      intro_lines << line
    end

    outro = ""
    if projects.any?
      last_project_index = lines.rindex { |line| line.match?(/^\d+\.\s+/) } || 0
      outro = lines[(last_project_index + 1)..]&.join.to_s
    end

    {
      intro: CvLatex.plain(intro_lines.join(" ")),
      intro_tex: CvLatex.latex_with_links(intro_lines.join(" ")),
      projects: projects,
      projects_tex: projects_tex,
      outro: CvLatex.plain(outro),
      outro_tex: CvLatex.latex_with_links(outro)
    }
  end

  def extract_email(body)
    body[/mailto:([^"'>\s]+)/, 1] || "yudaitnb@prg.is.titech.ac.jp"
  end

  def clean_data_text(value)
    CvLatex.plain(value, drop_spans: true)
  end

  def clean_data_tex(value)
    CvLatex.latex_with_links(value, drop_spans: true)
  end

  def clean_bib_text(value)
    CvLatex.plain(value.to_s.gsub(/[{}]/, ""))
  end

  def researchmap_presentations
    if @options[:researchmap_offline]
      return read_researchmap_cache
    end

    items = fetch_researchmap_presentations
    write_researchmap_cache(items)
    items
  rescue StandardError => e
    warn "Failed to fetch researchmap presentations: #{e.message}"
    warn "Using cached researchmap data from #{relative(@researchmap_cache)}" if File.exist?(@researchmap_cache)
    return read_researchmap_cache if File.exist?(@researchmap_cache)

    raise
  end

  def fetch_researchmap_presentations
    encoded_id = URI.encode_www_form_component(@options[:researchmap_id])
    url = "#{RESEARCHMAP_BASE_URL}/#{encoded_id}/presentations?limit=100"
    items = []

    loop do
      json = fetch_json(url)
      items.concat(Array(json["items"]))
      next_url = json.dig("_links", "next", "href")
      break if next_url.nil? || next_url.empty?

      url = next_url
    end

    items
  end

  def fetch_json(url)
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 20) do |http|
      http.request(request)
    end
    raise "HTTP #{response.code} from #{url}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def write_researchmap_cache(items)
    FileUtils.mkdir_p(File.dirname(@researchmap_cache))
    File.write(
      @researchmap_cache,
      JSON.pretty_generate(
        "fetched_at" => Time.now.utc.iso8601,
        "researchmap_id" => @options[:researchmap_id],
        "items" => items
      )
    )
  end

  def read_researchmap_cache
    data = JSON.parse(File.read(@researchmap_cache))
    Array(data["items"])
  end

  def researchmap_presentation_entry(item)
    title = localized_text(item["presentation_title"])
    event = localized_text(item["event"])
    event_url = researchmap_see_also_url(item)
    public_url = researchmap_public_url(item)

    {
      title: title,
      title_tex: CvLatex.link(public_url, title),
      date: format_researchmap_date(item["publication_date"] || item["from_event_date"]),
      subtitle: event,
      subtitle_tex: event_url ? CvLatex.link(event_url, event) : CvLatex.latex_raw_plain(event),
      meta: "",
      wide_subtitle: true,
      bullets: []
    }
  end

  def researchmap_sort_date(item)
    value = item["publication_date"] || item["from_event_date"] || ""
    Date.parse(value.length == 7 ? "#{value}-01" : value)
  rescue ArgumentError
    Date.new(0)
  end

  def format_researchmap_date(value)
    text = value.to_s
    if text.match?(/\A\d{4}-\d{2}/)
      year, month = text.split("-", 3)
      "#{MONTH_LABELS.fetch(month.to_i - 1)} #{year}"
    elsif text.match?(/\A\d{4}\z/)
      text
    else
      CvLatex.plain(text)
    end
  end

  def localized_text(value)
    case value
    when Hash
      value["en"] || value["ja"] || value.values.compact.first.to_s
    else
      value.to_s
    end
  end

  def researchmap_see_also_url(item)
    Array(item["see_also"]).find { |link| link["label"] == "url" }&.fetch("@id", nil)
  end

  def researchmap_public_url(item)
    id = item["rm:id"].to_s
    return item["@id"].to_s if id.empty?

    "https://researchmap.jp/#{@options[:researchmap_id]}/presentations/#{id}"
  end

  def publication_url(entry)
    doi = field(entry, :doi)
    return "https://doi.org/#{doi}" unless doi.empty?

    %i[url pdf html arxiv].map { |name| field(entry, name) }.find { |value| !value.empty? }.to_s
  end

  def publication_details_tex(entry, venue)
    parts = []
    parts << CvLatex.latex_raw_plain("In #{clean_bib_text(venue)}") unless venue.to_s.empty?
    parts << CvLatex.latex_raw_plain("Vol. #{field(entry, :volume)}") unless field(entry, :volume).empty?
    parts << CvLatex.latex_raw_plain("No. #{field(entry, :number)}") unless field(entry, :number).empty? || field(entry, :number).strip.empty?
    parts << CvLatex.latex_raw_plain("pp. #{field(entry, :pages)}") unless field(entry, :pages).empty?
    unless field(entry, :doi).empty?
      doi = field(entry, :doi)
      parts << "#{CvLatex.latex_raw_plain("DOI: ", strip: false)}#{CvLatex.link("https://doi.org/#{doi}", doi)}"
    end
    parts.join(CvLatex.latex_raw_plain(", ", strip: false))
  end

  def normalize_date(value)
    CvLatex.plain(value).gsub(/\bSept?\b/i, "Sep.")
                    .gsub(/\b(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Oct|Nov|Dec)\b/i, "\\1.")
                    .gsub(" - ", " -- ")
  end

  def year_range(years)
    return "" if years.empty?
    return years.first.to_s if years.length == 1

    "#{years.first} -- #{years.last}"
  end

  def field(entry, name)
    value = entry[name]
    value ? value.to_s : ""
  end

  def month_number(value)
    MONTHS.fetch(value.to_s.downcase[0, 3], 0)
  end

  def authors_tex(raw_names)
    names = raw_names.to_s.split(/\s+and\s+/).map { |name| format_person_name(name) }.reject(&:empty?)
    names.map do |name|
      escaped = CvLatex.latex_raw_plain(CvLatex.plain(name))
      name == "Yudai Tanabe" ? "\\textbf{#{escaped}}" : escaped
    end.join(", ")
  end

  def format_person_name(name)
    text = CvLatex.plain(name)
    if text.include?(",")
      last, first = text.split(",", 2).map(&:strip)
      [first, last].reject(&:empty?).join(" ")
    else
      text
    end
  end

  def compile_pdf(tex_path)
    command = ["latexmk", latexmk_engine_flag, "-interaction=nonstopmode", "-halt-on-error", File.basename(tex_path)]
    stdout, stderr, status = Open3.capture3(*command, chdir: @build_dir)
    return if status.success? && File.exist?(File.join(@build_dir, "CV.pdf"))

    log_path = File.join(@build_dir, "latexmk.log")
    File.write(log_path, [stdout, stderr].join("\n"))
    warn("LaTeX build failed. See #{relative(log_path)}")
    exit(status.exitstatus || 1)
  rescue Errno::ENOENT
    warn "latexmk was not found. Install a LaTeX distribution or run with --no-pdf to generate CV.tex only."
    exit 1
  end

  def latexmk_engine_flag
    case @options[:latex_engine]
    when "pdflatex" then "-pdf"
    when "xelatex" then "-xelatex"
    else
      raise ArgumentError, "Unsupported LaTeX engine: #{@options[:latex_engine]}"
    end
  end
end

options = {
  build_dir: File.join("cv", "build"),
  no_pdf: false,
  latex_engine: "xelatex",
  researchmap_id: "yudaitanabe",
  researchmap_offline: false,
  researchmap_cache: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby cv/generate_cv.rb [options]"
  parser.on("--build-dir DIR", "Directory for generated CV.tex and CV.pdf (default: cv/build)") do |dir|
    options[:build_dir] = dir
  end
  parser.on("--latex-engine ENGINE", "LaTeX engine: xelatex or pdflatex (default: xelatex)") do |engine|
    options[:latex_engine] = engine
  end
  parser.on("--no-pdf", "Generate only CV.tex; do not run latexmk") do
    options[:no_pdf] = true
  end
  parser.on("--researchmap-id ID", "researchmap permalink for invited talks (default: yudaitanabe)") do |id|
    options[:researchmap_id] = id
  end
  parser.on("--researchmap-cache FILE", "Cache file for researchmap presentations JSON") do |file|
    options[:researchmap_cache] = file
  end
  parser.on("--researchmap-offline", "Use cached researchmap data instead of fetching from the API") do
    options[:researchmap_offline] = true
  end
end.parse!

CvGenerator.new(options).run
