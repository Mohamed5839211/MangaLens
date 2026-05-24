---
trigger: always_on
---

Project: MangaLens
Role: Expert Mobile App Developer & Computer Vision Specialist.

System Rules & Behavioral Guidelines:
1. Localization & Layout:
   - The default UI language must be Arabic.
   - Full RTL (Right-to-Left) layout support is mandatory across the entire application interface.
   - English is supported only as a secondary language option.

2. Theme & UI/UX:
   - Dark mode is the absolute default and primary theme.
   - Include intuitive browser controls (Back, Forward, Refresh, Home) at the bottom.
   - Provide a non-intrusive floating action button (FAB) or gesture to trigger the translation.

3. Ad-Blocked In-App Browser:
   - Implement an embedded webview with network-level content blocking capabilities.
   - Use strict filtering rules (like EasyList) to completely block ads, pop-ups, and trackers on manga websites.

4. On-Device OCR Module:
   - Implement a robust on-device OCR engine (such as Google ML Kit) to accurately detect and extract text from speech bubbles (supporting Japanese, Korean, Chinese, and English).
   - Extract both the raw text content and the exact bounding boxes (coordinates and dimensions) of each detected text block.

5. Groq API Integration:
   - Use the Groq API (OpenAI-compatible endpoint, using models like llama3-70b-8192) for ultra-fast, low-latency text translation.
   - System Prompt for Groq: Instruct the model to act as a professional manga/manhwa translator, converting the text into natural, contextual Arabic while maintaining character tone and brevity to fit bubbles.

6. Advanced In-Place Translation (Torii Image Translator Style):
   - CRITICAL: DO NOT simply overlay the translated text using solid background boxes over the original image.
   - Step A (Bubble Cleaning / Inpainting): Apply advanced image processing techniques (e.g., OpenCV Inpainting, content-aware fill, or local color-matching algorithms) to seamlessly ERASE the original text from inside the speech bubble. This must leave a clean, empty bubble that perfectly matches its original background color/texture.
   - Step B (Text Rendering): Once the bubble is perfectly cleaned, dynamically render the translated Arabic text inside the empty bounding box, ensuring proper font scaling, line wrapping, and centering.

7. Code Quality:
   - Write highly modular, clean, and well-commented code.
   - Strictly decouple the UI layer from the computer vision (OCR/Inpainting) and translation logic.