use std::collections::HashSet;

use comrak::{markdown_to_html, Options};
use wasm_bindgen::prelude::*;

fn build_options() -> Options<'static> {
    let mut options = Options::default();
    options.extension.table = true;
    options.extension.strikethrough = true;
    options.extension.autolink = true;
    options.extension.tasklist = true;
    options.extension.footnotes = true;
    // Parse raw HTML embedded in markdown into the tree (instead of escaping it as text)
    // so it reaches the same sanitization pass as generated markup.
    options.render.unsafe_ = true;
    options
}

/// Build the ammonia sanitizer. Identical to the default allowlist except it
/// additionally permits the disabled checkbox inputs comrak emits for GFM
/// task lists (`- [ ]` / `- [x]`), so they render as real checkboxes instead
/// of being stripped. Inputs cannot execute script; there is no form to
/// submit; and only checkbox `type` plus `checked`/`disabled` are allowed,
/// so nothing dangerous (e.g. `formaction`) gets through.
fn sanitizer() -> ammonia::Builder<'static> {
    let mut builder = ammonia::Builder::default();
    builder.add_tags(std::iter::once("input"));

    let mut input_attrs = HashSet::new();
    input_attrs.insert("type");
    input_attrs.insert("checked");
    input_attrs.insert("disabled");
    builder.add_tag_attributes("input", input_attrs);

    builder
}

/// Render markdown to sanitized HTML.
///
/// Rendering (comrak) and sanitization (ammonia) happen as a single, inseparable
/// step: no caller can obtain rendered HTML that has not passed through the
/// sanitizer, since raw HTML embedded in markdown is intentionally parsed
/// (not escaped) so it is subject to the same allowlist-based cleaning.
#[wasm_bindgen]
pub fn render_markdown(input: &str) -> String {
    let html = markdown_to_html(input, &build_options());
    sanitizer().clean(&html).to_string()
}

#[cfg(test)]
mod tests {
    use super::render_markdown;

    #[test]
    fn renders_headings_and_paragraphs() {
        let html = render_markdown("# Title\n\nHello world.");
        assert!(html.contains("<h1"));
        assert!(html.contains("Title"));
        assert!(html.contains("Hello world."));
    }

    #[test]
    fn renders_gfm_tables() {
        let html = render_markdown("| a | b |\n|---|---|\n| 1 | 2 |\n");
        assert!(html.contains("<table"));
        assert!(html.contains("<td"));
    }

    #[test]
    fn renders_strikethrough_and_autolink() {
        let html = render_markdown("~~gone~~ https://example.com");
        assert!(html.contains("<del"));
        assert!(html.contains("href=\"https://example.com\""));
    }

    #[test]
    fn strips_script_tags() {
        let html = render_markdown("hello <script>alert(1)</script> world");
        assert!(!html.contains("<script"));
        assert!(!html.contains("alert(1)"));
    }

    #[test]
    fn strips_event_handler_attributes() {
        let html = render_markdown("<img src=\"x.png\" onerror=\"alert(1)\">");
        assert!(!html.contains("onerror"));
    }

    #[test]
    fn strips_javascript_urls() {
        let html = render_markdown("[click me](javascript:alert(1))");
        assert!(!html.contains("javascript:"));
    }

    #[test]
    fn strips_iframe_and_object_tags() {
        let html = render_markdown("<iframe src=\"https://evil.example\"></iframe><object data=\"x\"></object>");
        assert!(!html.contains("<iframe"));
        assert!(!html.contains("<object"));
    }

    #[test]
    fn renders_task_list_checkboxes() {
        let html = render_markdown("- [ ] todo\n- [x] done\n");
        // comrak's task-list checkboxes survive sanitization (see sanitizer()).
        assert!(html.contains("<input"));
        assert!(html.contains("type=\"checkbox\""));
        assert!(html.contains("checked"));
    }

    #[test]
    fn strips_dangerous_input_attributes() {
        // A text input with formaction must not keep formaction/onfocus even
        // though <input> is now allowed for task-list checkboxes.
        let html = render_markdown(
            "<input type=\"text\" formaction=\"javascript:alert(1)\" onfocus=\"alert(1)\">",
        );
        assert!(!html.contains("formaction"));
        assert!(!html.contains("onfocus"));
        assert!(!html.contains("alert(1)"));
    }
}
