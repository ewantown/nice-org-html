/*
;; nice-org-html.js
;;==============================================================================
;; Copyright (C) 2024, Ewan Townshend

;; Author: Ewan Townshend
;; URL: https://github.com/ewantown/nice-org-html
;; Version: 1.2

;;==============================================================================
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;; This file is not part of emacs.

;;==============================================================================
;; JS for html exported by et-org-html.el
 */

const preamble = document.getElementById("preamble");
const content = document.getElementById("content");
const postamble = document.getElementById("postamble");

const controls = document.getElementById("view-controls");
const toggleTocBtn = document.getElementById("toggle-toc");
const gotoTopBtn = document.getElementById("goto-top");
const toggleModeBtn = document.getElementById("toggle-mode");
const toc = document.getElementById("table-of-contents");

// Get and parse options passed in cookie string
const optCookie = document.cookie.split('; ').find(r => r.startsWith('options'));
const options = {};
if (optCookie) {
  optCookie.split('=')[1].split('__').forEach(pair => {
    const [key, val] = pair.split(':');
    if (key && val) {
      options[key] = val;
    }
  })
}

// Move sticky control bar (injected within preamble)
document.body.insertBefore(controls, content);

// Mode handling
function getMode() {
  let cookie = document.cookie.split('; ').find(r => r.startsWith('mode'))
  return cookie && cookie.split("=")[1];
}

function setMode(mode) {
  document.body.dataset.mode = mode;
  let thmCookie = document.cookie.split('; ').find(r => r.startsWith(mode));
  document.body.dataset.theme = thmCookie ? thmCookie.split('=')[1] : 'unknown';
  toggleModeBtn.innerHTML = (mode === 'light') ? '&#9789;' : '&#9788;';
  document.cookie = 'mode=' + mode;
}

// Initially, set mode based on stored cookie
let mode = getMode();
if (mode && ["light", "dark"].includes(mode)) {
  setMode(mode);
} else {  
  let prop = "prefers-color-scheme";
  let pref = (mode === "query") && window.matchMedia &&
    ["light", "dark"].find(s => window.matchMedia(`(${prop}: ${s})`).matches);
  setMode(pref || "dark"); // fallback: dark
}

// Mode toggling
toggleModeBtn.addEventListener('click', () => {
  setMode(document.body.dataset.mode === 'dark' ? 'light' : 'dark');
})


// Jump to top
let scrollY = document.documentElement.scrollTop;
window.addEventListener('scroll', () => {
  let atTop = document.documentElement.scrollTop <= preamble.offsetHeight;
  gotoTopBtn.dataset.show = !atTop + "";
});
gotoTopBtn.addEventListener('click', () => {
  window.scrollTo({
    top: 0,
    behavior: "smooth"
  });
})

// Table-of-contents toggling
if (toc) {
  toggleTocBtn.dataset.show = 'true';
  toggleTocBtn.addEventListener('click', () => {
    let showingToc = document.body.dataset.toc;
    scrollY = showingToc ? scrollY : document.documentElement.scrollTop;
    if (showingToc) {
      document.body.dataset.toc = '';
      document.documentElement.scrollTop = scrollY;
    } else {
      let tocHeight =
	Math.max(
	  window.innerHeight - controls.offsetHeight,
	  toc.offsetHeight
	);
      const header = document.getElementById("injected-header");
      if (header && (scrollY > header.offsetHeight)) {
	document.documentElement.scrollTop = preamble.offsetHeight;
      }
      toc.style.height = `${tocHeight}px`;
      document.body.dataset.toc = 'true';
    }
    toc.addEventListener('click', () => {
      if (document.body.dataset.toc) {
	document.body.dataset.toc = '';
	document.documentElement.scrollTop = scrollY;
      }
    })
  })
};

// Instrument anchor linking for sticky control bar
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', (e) => {
    e.preventDefault();
    const targetId = e.currentTarget.getAttribute('href');
    const target = document.querySelector(targetId);

    setTimeout(() => {
      const targetPos = target.getBoundingClientRect().top;
      let offset = targetPos + document.documentElement.scrollTop;
      offset -= controls.offsetHeight;
      window.scrollTo({
	top: offset,
	behavior: "smooth"
      });
    }, 0);
  });
});

function copyTextToClipboard(text) {
  // Make invisible textarea
  var textArea = document.createElement("textarea");
  textArea.style.position = 'fixed';
  textArea.style.top = 0;
  textArea.style.left = 0;
  textArea.style.width = '2em';
  textArea.style.height = '2em';
  textArea.style.padding = 0;
  textArea.style.border = 'none';
  textArea.style.outline = 'none';
  textArea.style.boxShadow = 'none';
  textArea.style.background = 'transparent';

  // Copy contents into it
  textArea.value = text;

  // Try to copy from it to clipboard
  document.body.appendChild(textArea);
  textArea.focus();
  textArea.select();
  var res;
  try {
    res = document.execCommand('copy');
  } catch (err) {
    res = false;
  }

  // Remove invisible textarea
  document.body.removeChild(textArea);

  return res;
}

// Handle the default header / footer drawers
const header = document.getElementById("generated-header");
const footer = document.getElementById("generated-footer");

if (header) {
  let toggle = header.querySelector("header nav input.nav-toggle");
  if (toggle) { toggle.checked = false; }
}
if (footer) {
  let nav = footer.querySelector("nav");
  let toggle = nav && nav.querySelector(".nav-toggle");
  let navList = nav && nav.querySelector(".nav-list");
  let navElem = navList && [...navList.querySelectorAll(".nav-item")];
  let numLink = navElem && navElem.length;
  if (numLink) {
    toggle.checked = false;
    toggle.addEventListener('change', () => {
      if (toggle.checked) {
	setTimeout(() => window.scrollTo({
	  behavior: 'smooth',
	  top: document.body.scrollHeight	  
	}), 88);
      }
   });
  }
}

function autoCompact() {
  var anchor, links, overlap, trivial;
  const domCompute = (node) => {
    if (node) {
      anchor = node.querySelector('.nav-title, .nav-author');
      links = node.querySelector('.nav-list');
      overlap = links.offsetLeft - 5 <= anchor.offsetLeft + anchor.offsetWidth;	
      trivial = links.offsetLeft === anchor.offsetLeft;
    }
  };
  let mediaMatch = window.matchMedia('(max-width: 768px)').matches;
  [header, footer].forEach(e => {
    if (e) {
      if (mediaMatch) {
	e.classList.add('compact');
      } else {
	domCompute(e);
	if (overlap && !trivial) {
	  e.classList.add('compact');
	} else {	
	  let clone = e.cloneNode(true);
	  clone.style.top = '-2000px';
	  clone.style.maxHeight = '0px';
	  clone.classList.remove('compact');
	  e.parentNode.insertBefore(clone, e);
	  domCompute(clone);
	  let toggle = e.querySelector('.nav-toggle');
	  if (!overlap && toggle && !toggle.checked) {
	    e.classList.remove('compact');
	  }
	  e.parentNode.removeChild(clone);
	}
      }
    }
  })
}

if ((header || footer)) {
  if (options.hasOwnProperty('layout')) {
    [header, footer].forEach(e => e ? e.classList.add(options.layout) : null);
  } else {
    autoCompact();
    window.addEventListener('resize', autoCompact);
  }
}

if (options.hasOwnProperty('src-lang') && options['src-lang'] == 't') {
  let labels = [...document.querySelectorAll('.srcLangLabel')];
  labels.forEach(l => l.style.display = 'inline-block');
}

if (options.hasOwnProperty('collapsing') && options.collapsing == 't') {
  let levels = [2, 3, 4, 5, 6];
  let containerPrefix = 'outline-container-';
  levels.forEach(l => {
    let containers = [...document.querySelectorAll(`.outline-${l}`)];
    containers.forEach(c => {
      let id = c.id.slice(containerPrefix.length);
      let headline = document.getElementById(id);
      let siblings = [...c.children].filter(child => child.id != id);
      headline.classList.add('collapsible');
      headline.addEventListener('click', () => {	
	if (headline.classList.contains('collapsed')) {
	  headline.classList.remove('collapsed');
	  siblings.forEach(child => {
	    child.classList.remove('hidden');
	  });	  
	} else {
	  headline.classList.add('collapsed');
	  siblings.forEach(child => {
	    child.classList.add('hidden');
	  });
	}
      })
    })
  })
}
