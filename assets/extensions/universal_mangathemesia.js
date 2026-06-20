function scrapePopularManga(document) {
  const list = [];
  const items = document.querySelectorAll(".bs, .bsx, .manga-card-v, .page-item-detail, .item"); 
  for (const item of items) {
    const a = item.querySelector("a");
    const img = item.querySelector("img");
    if (a && img) {
      let url = a.getAttribute("href") || "";
      if (url.startsWith("/")) url = window.location.origin + url;
      
      let imgUrl = img.getAttribute("data-lazy-src") || img.getAttribute("data-src") || img.getAttribute("src") || "";
      let title = a.getAttribute("title") || 
                  item.querySelector(".tt, .manga-title, .title, .post-title, h3, h2")?.innerText?.trim() || 
                  img.getAttribute("title") || img.getAttribute("alt") || 
                  a.innerText?.trim() || "";
                  
      // Avoid pushing completely empty items
      if (url && (title || imgUrl)) {
        list.push({ url: url, title: title.trim(), imageUrl: imgUrl.trim() });
      }
    }
  }
  return list;
}

function scrapeMangaDetails(document) {
  const title = document.querySelector(".entry-title, .infox h1")?.innerText?.trim();
  const description = document.querySelector(".entry-content, .desc")?.innerText?.trim();
  const img = document.querySelector(".thumb img");
  let imgUrl = img ? (img.getAttribute("data-src") || img.getAttribute("src")) : null;
  const author = document.querySelector(".infox .author i, .tsinfo .author")?.innerText?.trim();
  
  return {
    title: title,
    description: description,
    imageUrl: imgUrl,
    author: author,
  };
}

function scrapeChapters(document) {
  const list = [];
  const items = document.querySelectorAll("#chapterlist li, .eplister li");
  for (const item of items) {
    // Avoid locked chapters if any
    if (item.classList.contains("locked-badge") || item.querySelector(".locked-badge")) continue;
    
    const a = item.querySelector("a");
    if (a) {
      let url = a.getAttribute("href");
      if (url.startsWith("/")) {
        url = window.location.origin + url;
      }
      list.push({
        url: url,
        name: item.querySelector(".chapternum")?.innerText?.trim() || a.innerText?.trim(),
        date: item.querySelector(".chapterdate")?.innerText?.trim()
      });
    }
  }
  return list;
}

function scrapeChapterPages(document) {
  const list = [];
  const items = document.querySelectorAll("#readerarea img, #readerArea img");
  for (const img of items) {
    let url = img.getAttribute("data-src") || img.getAttribute("src");
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
