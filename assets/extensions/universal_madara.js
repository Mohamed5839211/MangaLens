function scrapePopularManga(document) {
  const list = [];
  const items = document.querySelectorAll(".page-item-detail, .manga");
  for (const item of items) {
    const a = item.querySelector("a, h3 a");
    const img = item.querySelector("img");
    if (a && img) {
      let url = a.getAttribute("href");
      if (url.startsWith("/")) {
        url = window.location.origin + url;
      }
      let imgUrl = img.getAttribute("data-src") || img.getAttribute("data-lazy-src") || img.getAttribute("src");
      list.push({
        url: url,
        title: a.innerText || a.getAttribute("title") || "",
        imageUrl: imgUrl
      });
    }
  }
  return list;
}

function scrapeMangaDetails(document) {
  const title = document.querySelector(".post-title h1, .post-title h3")?.innerText?.trim();
  const description = document.querySelector(".description-summary, .summary__content")?.innerText?.trim();
  const img = document.querySelector(".summary_image img");
  let imgUrl = img ? (img.getAttribute("data-src") || img.getAttribute("data-lazy-src") || img.getAttribute("src")) : null;
  const author = document.querySelector(".author-content a")?.innerText?.trim();
  
  return {
    title: title,
    description: description,
    imageUrl: imgUrl,
    author: author,
  };
}

function scrapeChapters(document) {
  const list = [];
  const items = document.querySelectorAll("li.wp-manga-chapter");
  for (const item of items) {
    const a = item.querySelector("a");
    if (a) {
      let url = a.getAttribute("href");
      if (url.startsWith("/")) {
        url = window.location.origin + url;
      }
      list.push({
        url: url,
        name: a.innerText?.trim(),
        date: item.querySelector("i, .chapter-release-date")?.innerText?.trim()
      });
    }
  }
  return list;
}

function scrapeChapterPages(document) {
  const list = [];
  const items = document.querySelectorAll(".page-break img, .reading-content img");
  for (const img of items) {
    let url = img.getAttribute("data-src") || img.getAttribute("data-lazy-src") || img.getAttribute("src");
    if (url) {
      list.push(url.trim());
    }
  }
  return list;
}

window.ExtensionScraper = {
  scrapePopularManga: scrapePopularManga,
  scrapeMangaDetails: scrapeMangaDetails,
  scrapeChapters: scrapeChapters,
  scrapeChapterPages: scrapeChapterPages
};
