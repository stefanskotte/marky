// Marky app bridge. Runs in an isolated content world (page JavaScript is
// disabled), sharing only the DOM with the document.
(function () {
  "use strict";
  var hits = [];
  var current = -1;
  var lastQuery = "";

  function content() { return document.getElementById("content") || document.body; }

  function clearFind() {
    hits.forEach(function (m) {
      var parent = m.parentNode;
      if (!parent) return;
      parent.replaceChild(document.createTextNode(m.textContent), m);
      parent.normalize();
    });
    hits = [];
    current = -1;
  }

  function collectTextNodes(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        var p = n.parentNode;
        if (!n.nodeValue || !p) return NodeFilter.FILTER_REJECT;
        var tag = p.nodeName;
        if (tag === "STYLE" || tag === "SCRIPT" || tag === "NOSCRIPT") return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    return nodes;
  }

  function highlightAll(query) {
    var q = query.toLocaleLowerCase();
    collectTextNodes(content()).forEach(function (node) {
      var text = node.nodeValue;
      var lower = text.toLocaleLowerCase();
      var idx = lower.indexOf(q);
      if (idx < 0) return;
      var frag = document.createDocumentFragment();
      var pos = 0;
      while (idx >= 0) {
        if (idx > pos) frag.appendChild(document.createTextNode(text.slice(pos, idx)));
        var mark = document.createElement("mark");
        mark.className = "marky-hit";
        mark.textContent = text.slice(idx, idx + q.length);
        frag.appendChild(mark);
        hits.push(mark);
        pos = idx + q.length;
        idx = lower.indexOf(q, pos);
      }
      if (pos < text.length) frag.appendChild(document.createTextNode(text.slice(pos)));
      node.parentNode.replaceChild(frag, node);
    });
  }

  function select(i) {
    if (current >= 0 && hits[current]) hits[current].classList.remove("current");
    current = i;
    var m = hits[current];
    if (!m) return;
    m.classList.add("current");
    // Open collapsed <details> that hide the match.
    for (var p = m.parentElement; p; p = p.parentElement) {
      if (p.tagName === "DETAILS" && !p.open) p.open = true;
    }
    m.scrollIntoView({ block: "center", inline: "nearest" });
  }

  // direction: 0 = new search, 1 = next, -1 = previous.
  function find(query, direction) {
    if (direction === 0 || query !== lastQuery || hits.length === 0) {
      clearFind();
      lastQuery = query;
      if (!query) return { count: 0, index: 0 };
      highlightAll(query);
      if (hits.length === 0) return { count: 0, index: 0 };
      // Start at the first match at or below the current scroll position.
      var start = 0;
      for (var i = 0; i < hits.length; i++) {
        if (hits[i].getBoundingClientRect().top >= 0) { start = i; break; }
      }
      select(direction === -1 ? (start - 1 + hits.length) % hits.length : start);
    } else {
      select((current + direction + hits.length) % hits.length);
    }
    return { count: hits.length, index: current + 1 };
  }

  window.marky = {
    setContent: function (html) {
      hits = [];
      current = -1;
      lastQuery = "";
      var y = window.scrollY;
      content().innerHTML = html;
      window.scrollTo(0, y);
    },
    setStyle: function (css) {
      var el = document.getElementById("marky-vars");
      if (el) el.textContent = css;
    },
    scrollToId: function (id) {
      var el = document.getElementById(id);
      if (el) el.scrollIntoView({ block: "start" });
    },
    find: find,
    clearFind: function () { clearFind(); lastQuery = ""; },
  };
})();
