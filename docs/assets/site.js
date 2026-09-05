(function () {
  const themeKey = "skilltree-theme";
  const root = document.documentElement;
  const toolbar = document.getElementById("site-toolbar");
  const button = document.getElementById("theme-toggle");
  const progress = document.getElementById("reading-progress");
  const scrollTopButton = document.getElementById("scroll-top");

  const themeIcons = {
    light:
      '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M20.2 15.5A8.5 8.5 0 0 1 8.5 3.8 8.5 8.5 0 1 0 20.2 15.5Z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    dark:
      '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 2v2.1M12 19.9V22M4.93 4.93l1.48 1.48M17.59 17.59l1.48 1.48M2 12h2.1M19.9 12H22M4.93 19.07l1.48-1.48M17.59 6.41l1.48-1.48" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>'
  };

  function mountToolbar() {
    if (!toolbar || !button) {
      return;
    }

    const navigation = document.querySelector("nav.app-nav");
    if (!navigation) {
      return;
    }

    if (navigation.parentElement !== toolbar) {
      toolbar.insertBefore(navigation, button);
    }

    toolbar.classList.toggle(
      "has-navigation",
      navigation.textContent.trim().length > 0
    );
  }

  function updateThemeUI(theme) {
    const dark = theme === "dark";
    const meta = document.querySelector('meta[name="theme-color"]');
    const icon = button && button.querySelector("span");

    if (meta) {
      meta.setAttribute("content", dark ? "#050d15" : "#eef3f6");
    }

    if (button) {
      const label = dark ? "切换到浅色主题" : "切换到深色主题";
      button.setAttribute("aria-label", label);
      button.setAttribute("aria-pressed", String(dark));
      button.setAttribute("title", label);
    }

    if (icon) {
      icon.innerHTML = dark ? themeIcons.dark : themeIcons.light;
    }
  }

  function setTheme(theme) {
    root.dataset.theme = theme;
    try {
      localStorage.setItem(themeKey, theme);
    } catch (error) {
      // Private browsing or blocked storage should not break theme switching.
    }
    updateThemeUI(theme);
  }

  let scrollFrame = 0;

  function updateScrollChrome() {
    const documentElement = document.documentElement;
    const scrollableHeight = Math.max(
      documentElement.scrollHeight - window.innerHeight,
      0
    );
    const progressValue = scrollableHeight
      ? Math.min(Math.max(window.scrollY / scrollableHeight, 0), 1)
      : 0;
    const percentage = Math.round(progressValue * 100);

    if (progress) {
      progress.style.setProperty("--reading-progress", String(progressValue));
      progress.setAttribute("aria-valuenow", String(percentage));
    }

    root.classList.toggle("is-scrolled", window.scrollY > 10);

    if (scrollTopButton) {
      scrollTopButton.hidden = window.scrollY < 420;
    }
  }

  function scheduleScrollChromeUpdate() {
    if (scrollFrame) {
      return;
    }

    scrollFrame = window.requestAnimationFrame(function () {
      scrollFrame = 0;
      updateScrollChrome();
    });
  }

  function focusSearch() {
    const input = document.querySelector(
      '.sidebar .search input[type="search"], .search input[type="search"]'
    );
    if (!input) {
      return;
    }

    const sidebar = document.querySelector(".sidebar");
    if (sidebar && window.innerWidth <= 768 && document.body.classList.contains("close")) {
      const toggle = document.querySelector(".sidebar-toggle");
      if (toggle) toggle.click();
    }

    input.focus({ preventScroll: true });
    input.select();
  }

  if (button) {
    button.addEventListener("click", function () {
      setTheme(root.dataset.theme === "dark" ? "light" : "dark");
    });
  }

  const skipLink = document.querySelector(".skip-link");
  if (skipLink) {
    skipLink.addEventListener("click", function (event) {
      event.preventDefault();
      const content = document.querySelector(".markdown-section");
      if (content) {
        content.setAttribute("tabindex", "-1");
        content.focus({ preventScroll: true });
        content.scrollIntoView({ block: "start" });
      }
    });
  }

  if (scrollTopButton) {
    scrollTopButton.addEventListener("click", function () {
      window.scrollTo({
        top: 0,
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
          ? "auto"
          : "smooth"
      });
    });
  }

  window.addEventListener("scroll", scheduleScrollChromeUpdate, {
    passive: true
  });
  window.addEventListener("resize", scheduleScrollChromeUpdate);
  document.addEventListener("keydown", function (event) {
    const target = event.target;
    const isEditing =
      target &&
      (target.tagName === "INPUT" ||
        target.tagName === "TEXTAREA" ||
        target.tagName === "SELECT" ||
        target.isContentEditable);

    if (!isEditing && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault();
      focusSearch();
      return;
    }

    if (event.key === "/" && !isEditing && !event.altKey && !event.shiftKey) {
      event.preventDefault();
      focusSearch();
    }
  });

  updateThemeUI(root.dataset.theme || "light");
  updateScrollChrome();

  function isSourcePath(path) {
    return /(?:\.(?:cs|csproj|slnx|sql|txt|ps1|sh|ya?ml|json|xml)|\/(?:Dockerfile|apt-install-retry))$/i.test(
      path
    );
  }

  function resolveRepositoryPath(routeFile, linkPath) {
    const baseDirectory = routeFile.includes("/")
      ? routeFile.slice(0, routeFile.lastIndexOf("/") + 1)
      : "";
    const resolved = new URL(linkPath, `https://skilltree.local/${baseDirectory}`);
    return decodeURIComponent(resolved.pathname.replace(/^\//, ""));
  }

  function githubSourceUrl(path) {
    const encodedPath = path
      .split("/")
      .map(function (segment) {
        return encodeURIComponent(segment);
      })
      .join("/");
    return `https://github.com/DreamWalkerJK/SkillTree/blob/main/${encodedPath}`;
  }

  function protectMath(content) {
    const blocks = [];
    const codeFragments = [];
    const protectedFences = content.replace(
      /(^|\n)([ \t]*)(`{3,}|~{3,})[^\n]*\n[\s\S]*?\n\2\3(?=\n|$)/g,
      function (match, lineStart) {
        const placeholder = `SKILLTREECODE${codeFragments.length}TOKEN`;
        codeFragments.push(match.slice(lineStart.length));
        return `${lineStart}${placeholder}`;
      }
    );
    const protectedCode = protectedFences.replace(
      /(`+)([\s\S]*?)\1/g,
      function (match) {
        const placeholder = `SKILLTREECODE${codeFragments.length}TOKEN`;
        codeFragments.push(match);
        return placeholder;
      }
    );
    const protectedContent = protectedCode.replace(
      /(^|[^\\])\$\$([\s\S]*?)\$\$|(^|[^\\])\$([^\n$]+?)\$/g,
      function (match, blockPrefix, blockMath, inlinePrefix, inlineMath) {
        const prefix = blockMath !== undefined ? blockPrefix : inlinePrefix;
        const source = blockMath !== undefined ? blockMath : inlineMath;
        const displayMode = blockMath !== undefined;
        const placeholder = `SKILLTREEMATH${blocks.length}TOKEN`;

        blocks.push(
          window.katex.renderToString(source.trim(), {
            displayMode: displayMode,
            throwOnError: false,
            strict: false,
            output: "htmlAndMathml"
          })
        );

        return `${prefix}${placeholder}`;
      }
    );

    return {
      content: protectedContent.replace(
        /SKILLTREECODE(\d+)TOKEN/g,
        function (placeholder, index) {
          return codeFragments[Number(index)] || placeholder;
        }
      ),
      blocks: blocks
    };
  }

  function skillTreePlugin(hook, vm) {
    hook.mounted(function () {
      mountToolbar();
    });

    hook.beforeEach(function (content) {
      const routeFile = decodeURIComponent((vm.route && vm.route.file) || "");
      const linkedContent = content.replace(/\]\((<?)([^)\n]+?)(>?)\)/g, function (
        fullMatch,
        openingBracket,
        rawTarget
      ) {
        const target = rawTarget.trim().replace(/^<|>$/g, "");
        if (/^(?:https?:|mailto:|#)/i.test(target)) {
          return fullMatch;
        }

        const parts = target.split("#", 2);
        const path = parts[0];
        if (!isSourcePath(path)) {
          return fullMatch;
        }

        const resolvedPath = resolveRepositoryPath(routeFile, path);
        const fragment = parts[1] ? `#${parts[1]}` : "";
        return `](${githubSourceUrl(resolvedPath)}${fragment})`;
      });

      if (typeof window.katex !== "object") {
        return linkedContent;
      }

      const math = protectMath(linkedContent);
      vm.config.__skillTreeMath = math.blocks;
      return math.content;
    });

    hook.afterEach(function (html) {
      const blocks = vm.config.__skillTreeMath || [];
      const restored = html.replace(
        /SKILLTREEMATH(\d+)TOKEN/g,
        function (placeholder, index) {
          return blocks[Number(index)] || placeholder;
        }
      );

      vm.config.__skillTreeMath = [];
      return restored;
    });

    hook.doneEach(function () {
      mountToolbar();

      const content = document.querySelector(".markdown-section");
      if (!content) {
        return;
      }

      content.setAttribute("role", "main");
      content.setAttribute("id", "main-content");

      const searchInput = document.querySelector('.search input[type="search"]');
      if (searchInput) {
        searchInput.setAttribute("aria-label", "搜索知识库");
        searchInput.setAttribute("name", "search");
        searchInput.setAttribute("autocomplete", "off");
      }
      const searchResults = document.querySelector(".search .results-panel");
      if (searchResults) searchResults.setAttribute("aria-live", "polite");

      content.classList.remove("content-ready");
      window.requestAnimationFrame(function () {
        content.classList.add("content-ready");
      });

      content.querySelectorAll("table").forEach(function (table) {
        const parent = table.parentElement;
        if (
          !parent ||
          parent.classList.contains("table-scroll") ||
          parent.classList.contains("table-wrapper")
        ) {
          return;
        }

        const wrapper = document.createElement("div");
        wrapper.className = "table-scroll";
        wrapper.setAttribute("role", "region");
        wrapper.setAttribute("aria-label", "数据表，可横向滚动");
        wrapper.setAttribute("tabindex", "0");
        parent.insertBefore(wrapper, table);
        wrapper.appendChild(table);
      });

      content.querySelectorAll('a[href^="http"]:not([target="_blank"])').forEach(
        function (link) {
          link.setAttribute("target", "_blank");
          link.setAttribute("rel", "noopener noreferrer");
        }
      );

      scheduleScrollChromeUpdate();

    });
  }

  window.$docsify = window.$docsify || {};
  window.$docsify.plugins = [skillTreePlugin].concat(
    window.$docsify.plugins || []
  );
})();
