const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

const evascansJsExtension = `
function getPopularManga() {
    var list = [];
    var bad = ['read','home','contact','about','discord','patreon','18+'];
    
    function isGoodTitle(t) {
        if (!t || t.length < 2 || t.length > 100) return false;
        var l = t.toLowerCase();
        for (var i=0; i<bad.length; i++) { if (l.includes(bad[i])) return false; }
        return true;
    }

    function isMangaUrl(href) {
        if (!href) return false;
        var l = href.toLowerCase();
        return l.includes('/manga/') || l.includes('/comic/') || l.includes('/series/');
    }

    var elements = document.querySelectorAll('a');
    for (var i = 0; i < elements.length; i++) {
        var a = elements[i];
        if (!isMangaUrl(a.href)) continue;
        
        var img = a.querySelector('img');
        if (!img) {
            // Try parent or siblings
            if (a.parentElement) img = a.parentElement.querySelector('img');
        }
        
        if (img) {
            var title = a.title || a.innerText.trim();
            if (!title && img.alt) title = img.alt.trim();
            
            var src = img.src || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || '';
            
            if (title && src && isGoodTitle(title)) {
                // Check if duplicate
                var exists = false;
                for (var j=0; j<list.length; j++) {
                    if (list[j].url === a.href) { exists = true; break; }
                }
                if (!exists) {
                    list.push({ title: title, url: a.href, coverUrl: src });
                }
            }
        }
    }
    return JSON.stringify(list);
}
`;

async function testSource(url, name) {
    console.log(`\n===========================================`);
    console.log(`Testing Source: ${name} (${url})`);
    console.log(`===========================================`);
    
    const browser = await puppeteer.launch({ headless: 'new' });
    const page = await browser.newPage();
    
    // Disable CSS/Images to speed up if needed, but we need images for data-src
    
    try {
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
        
        // Wait a bit for cloudflare if any
        await new Promise(r => setTimeout(r, 3000));
        
        // Scroll down a few times to trigger lazy loading
        for (let i = 0; i < 4; i++) {
            await page.evaluate(() => window.scrollBy(0, 1500));
            await new Promise(r => setTimeout(r, 600));
        }
        
        // Inject JS Extension
        await page.evaluate(evascansJsExtension);
        
        // Run getPopularManga
        const result = await page.evaluate(() => {
            return getPopularManga();
        });
        
        const parsed = JSON.parse(result);
        console.log(`✅ Success! Found ${parsed.length} mangas.`);
        if (parsed.length > 0) {
            console.log(`First 3 items:`);
            console.dir(parsed.slice(0, 3));
        } else {
            console.log(`❌ No manga found. Extension might need tuning for this site.`);
        }
    } catch (err) {
        console.error(`❌ Error testing ${name}:`, err.message);
    } finally {
        await browser.close();
    }
}

(async () => {
    console.log("🚀 Starting JS Extension Scraper Tests...");
    await testSource('https://evascans.org', 'EvaScans');
    await testSource('https://www.kunmanga.co.uk', 'KunManga');
    console.log("\n🏁 Testing complete.");
})();
