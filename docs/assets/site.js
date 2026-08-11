(function () {
  const themeKey = "skilltree-theme";
  const root = document.documentElement;

  function setTheme(theme) {
    root.dataset.theme = theme;
    localStorage.setItem(themeKey, theme);

    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) {
      meta.setAttribute("content", theme === "dark" ? "#0d1117" : "#f8fafc");
    }
  }

  const button = document.getElementById("theme-toggle");
  if (button) {
    button.addEventListener("click", function () {
      setTheme(root.dataset.theme === "dark" ? "light" : "dark");
    });
  }

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

  function skillTreePlugin(hook, vm) {
    hook.beforeEach(function (content) {
      const routeFile = decodeURIComponent((vm.route && vm.route.file) || "");
      return content.replace(/\]\((<?)([^)\n]+?)(>?)\)/g, function (
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
    });

    hook.doneEach(function () {
      if (typeof window.renderMathInElement !== "function") {
        return;
      }

      const content = document.querySelector(".markdown-section");
      if (!content) {
        return;
      }

      window.renderMathInElement(content, {
        delimiters: [
          { left: "$$", right: "$$", display: true },
          { left: "\\[", right: "\\]", display: true },
          { left: "\\(", right: "\\)", display: false },
          { left: "$", right: "$", display: false }
        ],
        throwOnError: false,
        strict: false
      });
    });
  }

  window.$docsify = window.$docsify || {};
  window.$docsify.plugins = [skillTreePlugin].concat(
    window.$docsify.plugins || []
  );
})();
