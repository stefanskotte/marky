// Marky renderer. Runs inside JavaScriptCore (no DOM), both in the app and in
// the Quick Look extension. Depends on markdown-it, markdown-it-footnote and
// highlight.js having been evaluated first. Entry point: markyRender(src, opts)
// → JSON string { html, headings: [{level, text, id}], title }.
(function () {
  "use strict";
  var g = globalThis;

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  // GitHub-style heading slugs.
  function slugify(s) {
    return s
      .trim()
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, "")
      .replace(/\s/g, "-");
  }

  function headingText(inline) {
    if (!inline || !inline.children) return "";
    return inline.children
      .filter(function (t) { return t.type === "text" || t.type === "code_inline"; })
      .map(function (t) { return t.content; })
      .join("");
  }

  // Heading ids + outline.
  function anchorsPlugin(md) {
    md.core.ruler.push("marky_anchors", function (state) {
      var toks = state.tokens, used = {}, heads = [];
      for (var i = 0; i < toks.length; i++) {
        if (toks[i].type !== "heading_open") continue;
        var text = headingText(toks[i + 1]);
        var base = slugify(text) || "section", slug = base, n = 1;
        while (used[slug]) slug = base + "-" + n++;
        used[slug] = true;
        toks[i].attrSet("id", slug);
        heads.push({ level: +toks[i].tag.slice(1), text: text, id: slug });
      }
      state.env.headings = heads;
    });
  }

  // GitHub task lists: "- [ ] todo" / "- [x] done".
  function taskListPlugin(md) {
    md.core.ruler.push("marky_tasks", function (state) {
      var toks = state.tokens;
      for (var i = 2; i < toks.length; i++) {
        var t = toks[i];
        if (t.type !== "inline") continue;
        if (toks[i - 1].type !== "paragraph_open" || toks[i - 2].type !== "list_item_open") continue;
        var m = /^\[([ xX])\][ \t]+/.exec(t.content);
        if (!m) continue;
        var first = t.children[0];
        if (!first || first.type !== "text" || first.content.indexOf(m[0]) !== 0) continue;
        first.content = first.content.slice(m[0].length);
        var cb = new state.Token("html_inline", "", 0);
        cb.content = '<input type="checkbox" class="task-list-item-checkbox" disabled' +
          (m[1] === " " ? "" : " checked") + "> ";
        t.children.unshift(cb);
        toks[i - 2].attrJoin("class", "task-list-item");
        for (var j = i - 3; j >= 0; j--) {
          var tj = toks[j];
          if ((tj.type === "bullet_list_open" || tj.type === "ordered_list_open") &&
              tj.level === toks[i - 2].level - 1) {
            if ((tj.attrGet("class") || "").indexOf("contains-task-list") < 0) {
              tj.attrJoin("class", "contains-task-list");
            }
            break;
          }
        }
      }
    });
  }

  // GitHub alerts: "> [!NOTE]", TIP, IMPORTANT, WARNING, CAUTION.
  function alertsPlugin(md) {
    var titles = { note: "Note", tip: "Tip", important: "Important", warning: "Warning", caution: "Caution" };
    md.core.ruler.push("marky_alerts", function (state) {
      var toks = state.tokens;
      for (var i = 0; i < toks.length - 2; i++) {
        if (toks[i].type !== "blockquote_open" || toks[i + 1].type !== "paragraph_open") continue;
        var inline = toks[i + 2];
        var m = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/i.exec(inline.content);
        if (!m) continue;
        var kind = m[1].toLowerCase();
        toks[i].attrJoin("class", "markdown-alert markdown-alert-" + kind);
        var ch = inline.children;
        if (ch.length && ch[0].type === "text") {
          ch[0].content = ch[0].content.replace(/^\[!\w+\][ \t]*/, "");
          if (!ch[0].content) {
            ch.shift();
            if (ch.length && (ch[0].type === "softbreak" || ch[0].type === "hardbreak")) ch.shift();
          }
        }
        var title = new state.Token("html_inline", "", 0);
        title.content = '<span class="markdown-alert-title">' + titles[kind] + "</span>";
        ch.unshift(title);
      }
    });
  }

  // YAML front matter → small collapsible metadata table.
  function splitFrontMatter(src) {
    var m = /^---[ \t]*\r?\n([\s\S]*?)\r?\n(---|\.\.\.)[ \t]*(\r?\n|$)/.exec(src);
    if (!m) return { body: src, html: "" };
    var rows = m[1].split(/\r?\n/).map(function (line) {
      var kv = /^([^:#\s][^:]*):\s*(.*)$/.exec(line);
      if (!kv) return "";
      return "<tr><th>" + escapeHtml(kv[1].trim()) + "</th><td>" +
        escapeHtml(kv[2].replace(/^["']|["']$/g, "")) + "</td></tr>";
    }).join("");
    var html = rows
      ? '<details class="front-matter"><summary>Front matter</summary><table>' + rows + "</table></details>\n"
      : "";
    return { body: src.slice(m[0].length), html: html };
  }

  var cache = {};

  function makeMd(opts) {
    var key = JSON.stringify(opts);
    if (cache[key]) return cache[key];
    var md = g.markdownit({
      html: true,
      linkify: true,
      typographer: !!opts.typographer,
      highlight: function (code, lang) {
        if (!opts.highlight || !lang || !g.hljs) return "";
        lang = lang.toLowerCase();
        if (!g.hljs.getLanguage(lang)) return "";
        try {
          return g.hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
        } catch (e) {
          return "";
        }
      },
    });
    if (g.markdownitFootnote) md.use(g.markdownitFootnote);
    md.use(taskListPlugin).use(alertsPlugin).use(anchorsPlugin);

    // Tables scroll horizontally instead of blowing out the layout.
    md.renderer.rules.table_open = function () { return '<div class="table-wrap"><table>\n'; };
    md.renderer.rules.table_close = function () { return "</table></div>\n"; };

    cache[key] = md;
    return md;
  }

  g.markyRender = function (src, opts) {
    opts = opts || {};
    var md = makeMd({ highlight: opts.highlight !== false, typographer: opts.typographer !== false });
    var fm = splitFrontMatter(String(src).replace(/^﻿/, ""));
    var env = {};
    var html = fm.html + md.render(fm.body, env);
    var headings = env.headings || [];
    var h1 = headings.filter(function (h) { return h.level === 1; })[0];
    return JSON.stringify({ html: html, headings: headings, title: h1 ? h1.text : null });
  };
})();
