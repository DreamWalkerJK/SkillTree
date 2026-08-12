(function () {
  const themeKey = "skilltree-theme";
  const root = document.documentElement;
  const toolbar = document.getElementById("site-toolbar");
  const button = document.getElementById("theme-toggle");

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
      meta.setAttribute("content", dark ? "#0b111a" : "#f3f6fa");
    }

    if (button) {
      const label = dark ? "切换到浅色主题" : "切换到深色主题";
      button.setAttribute("aria-label", label);
      button.setAttribute("aria-pressed", String(dark));
      button.setAttribute("title", label);
    }

    if (icon) {
      icon.textContent = dark ? "☀" : "☾";
    }
  }

  function setTheme(theme) {
    root.dataset.theme = theme;
    localStorage.setItem(themeKey, theme);
    updateThemeUI(theme);
  }

  if (button) {
    button.addEventListener("click", function () {
      setTheme(root.dataset.theme === "dark" ? "light" : "dark");
    });
  }

  updateThemeUI(root.dataset.theme || "light");

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

    });
  }

  window.$docsify = window.$docsify || {};
  window.$docsify.plugins = [skillTreePlugin].concat(
    window.$docsify.plugins || []
  );
})();
