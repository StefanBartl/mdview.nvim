use std::collections::HashSet;

use comrak::nodes::{AstNode, NodeValue};
use comrak::{format_html, parse_document, Arena, Options};
use wasm_bindgen::prelude::*;

fn build_options() -> Options<'static> {
    let mut options = Options::default();
    options.extension.table = true;
    options.extension.strikethrough = true;
    options.extension.autolink = true;
    options.extension.tasklist = true;
    options.extension.footnotes = true;
    // Parse raw HTML embedded in markdown into the tree (instead of escaping it as text)
    // so it reaches the same sanitization pass as generated markup. Also required so the
    // inline source-position <span>s we splice in as HtmlInline are emitted verbatim.
    options.render.unsafe_ = true;
    // Emit `data-sourcepos="startLine:col-endLine:col"` on block elements so the
    // client can map a Neovim cursor line to the matching DOM node and scroll it
    // into view precisely (see src/client/main.ts). Kept through sanitization by
    // allowing the attribute in sanitizer().
    options.render.sourcepos = true;
    options
}

/// Escape text so it is safe as HTML element content. Used when we replace a
/// Text/Code node's value with hand-built `<span>` markup (HtmlInline) — comrak
/// no longer escapes it for us, so we must.
fn escape_html_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            _ => out.push(c),
        }
    }
    out
}

/// Wrap inline Text and inline Code runs in a `<span data-sp="sl:sc:el:ec">` that
/// carries the run's source position, so the client can place a caret at the exact
/// Neovim cursor column (browser.cursor_marker = "caret"). comrak's sourcepos
/// columns are 1-based **byte** columns, matching Neovim's byte-based cursor
/// column, so the mapping needs only a byte→UTF-16 conversion in the client.
///
/// Two runs are intentionally left alone:
///   * anything under an `Image` node — its Text children are serialized into the
///     `alt=""` attribute, where injected markup would be nonsense;
///   * fenced/indented code blocks — their content is a single block node re-
///     tokenized by the client highlighter, which would strip inner spans; the
///     caret falls back to the line marker inside them.
fn annotate_source_positions<'a>(node: &'a AstNode<'a>, in_image: bool) {
    let is_image = matches!(node.data.borrow().value, NodeValue::Image(_));
    let child_in_image = in_image || is_image;
    for child in node.children() {
        annotate_source_positions(child, child_in_image);
    }
    if in_image {
        return;
    }

    // Compute the replacement string under an immutable borrow, then swap it in
    // under a mutable borrow — never both at once.
    let replacement = {
        let d = node.data.borrow();
        let sp = d.sourcepos;
        match &d.value {
            NodeValue::Text(text) => Some(format!(
                "<span data-sp=\"{}:{}:{}:{}\">{}</span>",
                sp.start.line, sp.start.column, sp.end.line, sp.end.column,
                escape_html_text(text),
            )),
            NodeValue::Code(code) => Some(format!(
                "<span data-sp=\"{}:{}:{}:{}\"><code>{}</code></span>",
                sp.start.line, sp.start.column, sp.end.line, sp.end.column,
                escape_html_text(&code.literal),
            )),
            _ => None,
        }
    };
    if let Some(html) = replacement {
        node.data.borrow_mut().value = NodeValue::HtmlInline(html);
    }
}

/// Build the ammonia sanitizer. Identical to the default allowlist except it
/// additionally permits the disabled checkbox inputs comrak emits for GFM
/// task lists (`- [ ]` / `- [x]`), so they render as real checkboxes instead
/// of being stripped. Inputs cannot execute script; there is no form to
/// submit; and only checkbox `type` plus `checked`/`disabled` are allowed,
/// so nothing dangerous (e.g. `formaction`) gets through.
fn sanitizer() -> ammonia::Builder<'static> {
    let mut builder = ammonia::Builder::default();
    // `input` for task-list checkboxes; `span` for the inline source-position
    // wrappers (annotate_source_positions). Both carry no executable surface.
    builder.add_tags(["input", "span"].iter().copied());

    // Keep our source-position hints on every element so the client can do
    // line-accurate scroll sync (data-sourcepos, on blocks) and column-accurate
    // caret placement (data-sp, on inline spans). Both carry no executable
    // content — just "L:C…" digits — and can't be used to inject script.
    builder.add_generic_attributes(["data-sourcepos", "data-sp"].iter().copied());

    let mut input_attrs = HashSet::new();
    input_attrs.insert("type");
    input_attrs.insert("checked");
    input_attrs.insert("disabled");
    builder.add_tag_attributes("input", input_attrs);

    builder
}

/// Render markdown to sanitized HTML.
///
/// When `source_map` is true, inline text/code runs are wrapped in
/// `<span data-sp="…">` carrying their source position, for the column-accurate
/// cursor caret. It is off by default (the caller passes it only when
/// browser.cursor_marker = "caret") so documents aren't bloated with spans
/// otherwise.
///
/// Rendering (comrak) and sanitization (ammonia) happen as a single, inseparable
/// step: no caller can obtain rendered HTML that has not passed through the
/// sanitizer, since raw HTML embedded in markdown is intentionally parsed
/// (not escaped) so it is subject to the same allowlist-based cleaning.
#[wasm_bindgen]
pub fn render_markdown(input: &str, source_map: bool) -> String {
    let arena = Arena::new();
    let options = build_options();
    let root = parse_document(&arena, input, &options);
    if source_map {
        annotate_source_positions(root, false);
    }
    let mut html = Vec::new();
    // format_html only fails if the writer fails; a Vec writer never does.
    let _ = format_html(root, &options, &mut html);
    let html = String::from_utf8(html).unwrap_or_default();
    sanitizer().clean(&html).to_string()
}

#[cfg(test)]
mod tests {
    use super::render_markdown;

    #[test]
    fn renders_headings_and_paragraphs() {
        let html = render_markdown("# Title\n\nHello world.", false);
        assert!(html.contains("<h1"));
        assert!(html.contains("Title"));
        assert!(html.contains("Hello world."));
    }

    #[test]
    fn renders_gfm_tables() {
        let html = render_markdown("| a | b |\n|---|---|\n| 1 | 2 |\n", false);
        assert!(html.contains("<table"));
        assert!(html.contains("<td"));
    }

    #[test]
    fn renders_strikethrough_and_autolink() {
        let html = render_markdown("~~gone~~ https://example.com", false);
        assert!(html.contains("<del"));
        assert!(html.contains("href=\"https://example.com\""));
    }

    #[test]
    fn strips_script_tags() {
        let html = render_markdown("hello <script>alert(1)</script> world", false);
        assert!(!html.contains("<script"));
        assert!(!html.contains("alert(1)"));
    }

    #[test]
    fn strips_event_handler_attributes() {
        let html = render_markdown("<img src=\"x.png\" onerror=\"alert(1)\">", false);
        assert!(!html.contains("onerror"));
    }

    #[test]
    fn strips_javascript_urls() {
        let html = render_markdown("[click me](javascript:alert(1))", false);
        assert!(!html.contains("javascript:"));
    }

    #[test]
    fn strips_iframe_and_object_tags() {
        let html = render_markdown("<iframe src=\"https://evil.example\"></iframe><object data=\"x\"></object>", false);
        assert!(!html.contains("<iframe"));
        assert!(!html.contains("<object"));
    }

    #[test]
    fn renders_task_list_checkboxes() {
        let html = render_markdown("- [ ] todo\n- [x] done\n", false);
        // comrak's task-list checkboxes survive sanitization (see sanitizer()).
        assert!(html.contains("<input"));
        assert!(html.contains("type=\"checkbox\""));
        assert!(html.contains("checked"));
    }

    #[test]
    fn keeps_relative_link_href() {
        let html = render_markdown("[testlink](./docs/PoC.md)", false);
        eprintln!("RENDERED: {html}");
        assert!(html.contains("testlink"));
    }

    #[test]
    fn emits_sourcepos_for_scroll_sync() {
        let html = render_markdown("# One\n\nsecond line\n\nthird\n", false);
        eprintln!("SOURCEPOS: {html}");
        // block elements carry data-sourcepos so the client can map lines to nodes
        assert!(html.contains("data-sourcepos="));
    }

    #[test]
    fn strips_dangerous_input_attributes() {
        // A text input with formaction must not keep formaction/onfocus even
        // though <input> is now allowed for task-list checkboxes.
        let html = render_markdown(
            "<input type=\"text\" formaction=\"javascript:alert(1)\" onfocus=\"alert(1)\">",
            false,
        );
        assert!(!html.contains("formaction"));
        assert!(!html.contains("onfocus"));
        assert!(!html.contains("alert(1)"));
    }

    // ---- source-map mode (browser.cursor_marker = "caret") -----------------

    #[test]
    fn source_map_off_emits_no_inline_spans() {
        let html = render_markdown("plain **bold** text", false);
        assert!(!html.contains("data-sp="));
    }

    #[test]
    fn source_map_wraps_inline_text_with_byte_columns() {
        // "para " occupies byte columns 1..5, "bold" (inside **…**) 8..11.
        let html = render_markdown("para **bold** and end", true);
        eprintln!("SRCMAP: {html}");
        assert!(html.contains("data-sp=\"1:1:1:5\""));
        assert!(html.contains("<strong>"));
        assert!(html.contains("data-sp=\"1:8:1:11\""));
        // the wrapped text is still present and readable
        assert!(html.contains(">bold</span>"));
    }

    #[test]
    fn source_map_columns_are_byte_based_for_multibyte() {
        // "äöü z" is 5 chars but 8 bytes; on "# äöü z" the text run is byte
        // columns 3..10 — proving columns count bytes, matching Neovim.
        let html = render_markdown("# äöü z", true);
        eprintln!("SRCMAP-MB: {html}");
        assert!(html.contains("data-sp=\"1:3:1:10\""));
    }

    #[test]
    fn source_map_wraps_inline_code() {
        let html = render_markdown("a `code` b", true);
        eprintln!("SRCMAP-CODE: {html}");
        // inline code content is byte columns 4..7 (backticks excluded)
        assert!(html.contains("data-sp=\"1:4:1:7\""));
        assert!(html.contains("<code>code</code>"));
    }

    #[test]
    fn source_map_does_not_pollute_image_alt() {
        // The alt attribute must stay plain text — no injected <span>.
        let html = render_markdown("![my alt](img.png)", true);
        eprintln!("SRCMAP-IMG: {html}");
        assert!(html.contains("alt=\"my alt\""));
        assert!(!html.contains("alt=\"<span"));
    }

    #[test]
    fn source_map_still_strips_xss() {
        // Enabling source_map must not weaken sanitization.
        let html = render_markdown("hi <script>alert(1)</script> [x](javascript:alert(1))", true);
        assert!(!html.contains("<script"));
        assert!(!html.contains("javascript:"));
        assert!(!html.contains("alert(1)"));
    }
}
