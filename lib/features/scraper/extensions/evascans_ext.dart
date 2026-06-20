/// سكريبت JavaScript لاستخراج بيانات المانجا من مواقع WordPress Madara
/// مبني على أنماط Tachiyomi/Keiyoushi المثبتة عالمياً
/// يدعم: EvaScans, KunManga, وجميع مواقع قالب Madara
const String evascansJsExtension = r'''
function getPopularManga() {
    var list = [];

    // ── المحددات الدقيقة لقالب Madara (Tachiyomi-style) ──
    var cards = document.querySelectorAll('div.page-item-detail, div.row.c-tabs-item__task, div.c-tabs-item__task, div.manga__item, div.item');
    
    for (var i = 0; i < cards.length; i++) {
        var card = cards[i];
        
        // 1. استخراج العنوان من post-title (الطريقة الأكثر دقة)
        var titleEl = card.querySelector('.post-title h3 a, .post-title h5 a, .post-title a, h3.manga-title a, h3 a');
        if (!titleEl || !titleEl.href) continue;
        
        var url = titleEl.href;
        var title = titleEl.textContent.trim();
        
        // إزالة أي شارات (HOT, NEW) من العنوان
        var badges = titleEl.querySelectorAll('.manga-title-badges, .badge, .hot, .new, span');
        for (var b = 0; b < badges.length; b++) {
            title = title.replace(badges[b].textContent, '').trim();
        }
        
        // 2. استخراج صورة الغلاف
        var imgEl = card.querySelector('.item-thumb img, img.img-responsive, .manga-poster img, img');
        var coverUrl = '';
        if (imgEl) {
            coverUrl = imgEl.getAttribute('data-src') || imgEl.getAttribute('data-lazy-src') || imgEl.src || '';
        }
        
        // 3. تنظيف وفلترة
        if (!title || title.length < 2 || !url || !coverUrl) continue;
        title = title.replace(/\s+/g, ' ').trim();
        
        // 4. فلترة التكرار بالرابط المنسق
        var normUrl = url.replace(/\/+$/, '').toLowerCase();
        var exists = false;
        for (var j = 0; j < list.length; j++) {
            if (list[j].url.replace(/\/+$/, '').toLowerCase() === normUrl) { exists = true; break; }
        }
        if (!exists) {
            list.push({ title: title, url: url, coverUrl: coverUrl });
        }
    }
    
    // ── إذا لم يعمل Madara selector، نستخدم طريقة احتياطية ──
    if (list.length === 0) {
        var allImgs = document.querySelectorAll('img');
        var seenUrls = {};
        var seenTitles = {};
        
        for (var i = 0; i < allImgs.length; i++) {
            var img = allImgs[i];
            var a = img.closest ? img.closest('a') : null;
            if (!a) a = img.parentElement;
            if (!a || !a.href) continue;
            
            var href = a.href.toLowerCase();
            if (!(href.includes('/manga/') || href.includes('/comic/') || href.includes('/series/'))) continue;
            
            var url = a.href;
            var normUrl = url.replace(/\/+$/, '').toLowerCase();
            if (seenUrls[normUrl]) continue;
            
            var coverUrl = img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.src || '';
            if (!coverUrl) continue;
            
            // البحث عن العنوان الحقيقي
            var title = '';
            
            // أ. من أقرب .post-title
            var container = a.closest('.page-item-detail, .c-tabs-item__content, .item, .manga-card, .manga__item');
            if (container) {
                var tEl = container.querySelector('.post-title h3 a, .post-title h5 a, .post-title a, h3 a');
                if (tEl) title = tEl.textContent.trim();
            }
            
            // ب. استخراج العنوان من الرابط (URL Slug) وهو الأضمن والموثوق دائماً
            if (!title || title.length < 3 || /^(manga|cover|eva|narjis|resource|img|s\s*\d|i\d+)/i.test(title)) {
                var parts = url.split('/').filter(Boolean);
                var slug = parts[parts.length - 1]; // e.g., first-love-makeover
                if (slug) {
                    title = slug.replace(/-/g, ' ').replace(/\b\w/g, function(l){ return l.toUpperCase() });
                }
            }
            
            if (!title || title.length < 2) continue;
            
            // تنظيف العنوان
            title = title.replace(/\s+/g, ' ').replace(/^(Read|HOT|NEW)\s*/gi, '').trim();
            
            // فلتر التكرار
            var normTitle = title.toLowerCase();
            if (seenTitles[normTitle]) continue;
            
            seenUrls[normUrl] = true;
            seenTitles[normTitle] = true;
            list.push({ title: title, url: url, coverUrl: coverUrl });
        }
    }
    
    return JSON.stringify(list);
}

function searchManga() {
    return getPopularManga();
}

async function getMangaDetails() {
    // ── 1. استخراج العنوان (Madara style) ──
    var titleEl = document.querySelector('.post-title h1');
    var title = '';
    if (titleEl) {
        // نسخ العنصر وحذف الشارات منه
        var clone = titleEl.cloneNode(true);
        var badges = clone.querySelectorAll('.manga-title-badges, span, .badge');
        for (var i = 0; i < badges.length; i++) badges[i].remove();
        title = clone.textContent.trim();
    }
    if (!title) {
        var ogTitle = document.querySelector('meta[property="og:title"]');
        title = ogTitle ? ogTitle.content : (document.querySelector('h1')?.textContent.trim() || 'Unknown');
    }
    // تنظيف العنوان من اسم الموقع
    title = title.split(/\s*[-|–]\s*/)[0].trim();
    
    // ── 2. استخراج الوصف ──
    var descEl = document.querySelector('.summary__content, .description-summary .summary__content, div.description-summary, .manga-excerpt');
    var desc = '';
    if (descEl) {
        // حذف "Show more" وما شابه
        var clone = descEl.cloneNode(true);
        var extras = clone.querySelectorAll('a, .more-link, script');
        for (var i = 0; i < extras.length; i++) extras[i].remove();
        desc = clone.textContent.trim();
    }
    if (!desc || desc.length < 10) {
        var metaDesc = document.querySelector('meta[property="og:description"]') || document.querySelector('meta[name="description"]');
        if (metaDesc) desc = metaDesc.content;
    }
    
    // ── 3. استخراج المؤلف ──
    var authorEl = document.querySelector('.author-content a, .author-content, [href*="manga-author"]');
    var author = authorEl ? authorEl.textContent.trim() : '';
    if (author.includes('\n')) author = author.split('\n')[0].trim();
    
    // ── 4. جلب كل الفصول (Tachiyomi pattern) ──
    // الطريقة الأولى: POST إلى {mangaUrl}/ajax/chapters/ (الطريقة الجديدة)
    var currentUrl = window.location.href.replace(/\/+$/, '') + '/';
    try {
        var res = await fetch(currentUrl + 'ajax/chapters/', { 
            method: 'POST',
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
        });
        if (res.ok) {
            var html = await res.text();
            if (html && html.includes('wp-manga-chapter')) {
                var div = document.createElement('div');
                div.id = '_ajax_chapters_container';
                div.innerHTML = html;
                document.body.appendChild(div);
            }
        }
    } catch(e) {}
    
    // الطريقة الثانية: POST إلى admin-ajax.php (الطريقة القديمة)
    if (document.querySelectorAll('li.wp-manga-chapter').length === 0) {
        var mangaId = null;
        
        // البحث عن manga ID بأولوية (Tachiyomi pattern)
        var idEl = document.querySelector('input.rating-post-id');
        if (idEl) mangaId = idEl.value;
        
        if (!mangaId) {
            idEl = document.querySelector('#manga-chapters-holder');
            if (idEl) mangaId = idEl.getAttribute('data-id') || idEl.getAttribute('data-post-id');
        }
        
        if (!mangaId) {
            var scriptEl = document.querySelector('#wp-manga-js-extra');
            if (scriptEl) {
                var match = scriptEl.textContent.match(/"manga_id"\s*:\s*"?(\d+)"?/);
                if (match) mangaId = match[1];
            }
        }
        
        // Hidden input fallback
        if (!mangaId) {
            var hidden = document.querySelector('input[name="manga_id"], input#manga-id');
            if (hidden) mangaId = hidden.value;
        }
        
        if (mangaId) {
            try {
                var formData = new FormData();
                formData.append('action', 'manga_get_chapters');
                formData.append('manga', mangaId);
                var res = await fetch('/wp-admin/admin-ajax.php', { 
                    method: 'POST', 
                    body: formData,
                    headers: { 
                        'X-Requested-With': 'XMLHttpRequest',
                        'Referer': window.location.href 
                    }
                });
                if (res.ok) {
                    var html = await res.text();
                    if (html && html.includes('wp-manga-chapter')) {
                        var div = document.createElement('div');
                        div.id = '_ajax_chapters_container_old';
                        div.innerHTML = html;
                        document.body.appendChild(div);
                    }
                }
            } catch(e) {}
        }
    }
    
    // ── 5. تحليل الفصول ──
    var chapters = [];
    var chapterEls = document.querySelectorAll('li.wp-manga-chapter');
    
    if (chapterEls.length > 0) {
        // طريقة Madara الدقيقة
        for (var i = 0; i < chapterEls.length; i++) {
            var li = chapterEls[i];
            var a = li.querySelector('a');
            if (!a || !a.href) continue;
            
            var cTitle = a.textContent.trim().replace(/\s+/g, ' ');
            var dateEl = li.querySelector('.chapter-release-date i, .chapter-release-date');
            var cDate = dateEl ? dateEl.textContent.trim() : '';
            
            // فلتر التكرار
            var normUrl = a.href.replace(/\/+$/, '');
            var exists = false;
            for (var j = 0; j < chapters.length; j++) {
                if (chapters[j].url.replace(/\/+$/, '') === normUrl) { exists = true; break; }
            }
            if (!exists) {
                chapters.push({ title: cTitle, url: a.href, date: cDate });
            }
        }
    } else {
        // طريقة احتياطية للمواقع غير Madara
        var links = document.querySelectorAll('.chapter-list a, .chapters a, a[href*="chapter"], a[href*="ch-"]');
        for (var i = 0; i < links.length; i++) {
            var a = links[i];
            if (!a.href || !(a.href.includes('chapter') || a.href.includes('ch-'))) continue;
            var cTitle = a.textContent.trim().replace(/\s+/g, ' ');
            if (!cTitle || cTitle.length < 2) continue;
            
            var normUrl = a.href.replace(/\/+$/, '');
            var exists = false;
            for (var j = 0; j < chapters.length; j++) {
                if (chapters[j].url.replace(/\/+$/, '') === normUrl) { exists = true; break; }
            }
            if (!exists) {
                chapters.push({ title: cTitle, url: a.href, date: '' });
            }
        }
    }
    
    return JSON.stringify({
        title: title,
        description: desc,
        author: author,
        chapters: chapters
    });
}

function getChapterPages() {
    var imgs = [];
    // Madara reader selector (Tachiyomi pattern)
    var elements = document.querySelectorAll('.reading-content img, .page-break img, .wp-manga-chapter-img');
    
    if (elements.length === 0) {
        elements = document.querySelectorAll('img');
    }
    
    for (var i = 0; i < elements.length; i++) {
        var src = elements[i].getAttribute('data-src') || elements[i].getAttribute('data-lazy-src') || elements[i].src || '';
        src = src.trim();
        if (src && !src.includes('logo') && !src.includes('icon') && !src.includes('avatar') && !src.includes('ads') && src.length > 10) {
            imgs.push(src);
        }
    }
    return JSON.stringify(imgs);
}
''';
