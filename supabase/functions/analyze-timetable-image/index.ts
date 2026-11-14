import { TIMETABLE_JSON_SCHEMA } from "./schema.ts";
import { TIMETABLE_VISION_PROMPT } from "./prompt.ts";
import { validateAndNormalizeAiResponse } from "./validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Giới hạn kích thước ảnh tối đa (10 MB base64 payload)
const MAX_PAYLOAD_BYTES = 10 * 1024 * 1024;

// Simple in-memory rate limiter per IP (15 requests / phút)
interface RateLimitRecord {
  count: number;
  resetAt: number;
}
const rateLimitMap = new Map<string, RateLimitRecord>();

function checkRateLimit(clientIp: string): boolean {
  const now = Date.now();
  const record = rateLimitMap.get(clientIp);

  if (!record || now > record.resetAt) {
    rateLimitMap.set(clientIp, { count: 1, resetAt: now + 60000 });
    return true;
  }

  if (record.count >= 15) {
    return false;
  }

  record.count++;
  return true;
}

Deno.serve(async (req: Request) => {
  // 1. Xử lý preflight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 2. Kiểm tra phương thức HTTP
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Chỉ hỗ trợ phương thức POST." }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  // 3. Kiểm tra kích thước payload từ Header
  const contentLength = Number(req.headers.get("content-length") || "0");
  if (contentLength > MAX_PAYLOAD_BYTES) {
    return new Response(
      JSON.stringify({
        success: false,
        error: "Kích thước ảnh vượt quá giới hạn cho phép (tối đa 10 MB).",
      }),
      {
        status: 413,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  // 4. Kiểm tra Rate Limiting bảo vệ Free Tier
  const clientIp =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("cf-connecting-ip") ||
    "unknown_client";

  if (!checkRateLimit(clientIp)) {
    return new Response(
      JSON.stringify({
        success: false,
        error:
          "Bạn đã gửi quá nhiều yêu cầu phân tích trong thời gian ngắn. Vui lòng đợi 1 phút trước khi thử lại.",
      }),
      {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  // 5. Đọc biến môi trường an toàn từ Supabase Secrets
  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiApiKey || geminiApiKey.trim() === "") {
    console.error("[Auth Error] GEMINI_API_KEY chưa được thiết lập trên Supabase Secrets.");
    return new Response(
      JSON.stringify({
        success: false,
        error:
          "Cấu hình AI chưa hoàn tất: GEMINI_API_KEY chưa được thiết lập trên Supabase Edge Functions Secret.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  // Model ID chính thức theo yêu cầu và khuyến nghị từ Google API:
  // Google API phản hồi: "Please update your code to use models/gemini-3.8-flash for the latest features and improvements."
  const configuredModel = (Deno.env.get("GEMINI_MODEL") || "gemini-3.8-flash").trim();
  const apiVersion = "v1beta";

  // Danh sách model tương thích được Google hỗ trợ:
  // 1. gemini-3.8-flash (Model chuẩn khuyến nghị từ Google)
  // 2. gemini-3-flash-preview (Model dự phòng khi có demand spike)
  const candidateModels = [
    configuredModel,
    ...(configuredModel !== "gemini-3-flash-preview" ? ["gemini-3-flash-preview"] : []),
  ];

  try {
    // 6. Phân tích nội dung JSON từ client
    let body: any;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Dữ liệu JSON gửi lên không hợp lệ.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Chế độ chẩn đoán an toàn: liệt kê danh sách model mà API key có quyền truy cập
    if (body?.action === "list_models") {
      try {
        const listUrl = `https://generativelanguage.googleapis.com/${apiVersion}/models?key=${geminiApiKey}`;
        const listResp = await fetch(listUrl);
        const listData = await listResp.json();
        return new Response(JSON.stringify(listData), {
          status: listResp.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (err: any) {
        return new Response(
          JSON.stringify({ success: false, error: `Lỗi truy vấn danh sách model: ${err?.message || err}` }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    const { image, mimeType } = body || {};

    if (!image || typeof image !== "string" || image.trim() === "") {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Vui lòng cung cấp dữ liệu hình ảnh dạng Base64 hợp lệ.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const validMimes = ["image/jpeg", "image/png", "image/webp", "image/jpg"];
    const normalizedMime = (mimeType || "image/jpeg").toLowerCase();
    if (!validMimes.includes(normalizedMime)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `Định dạng ảnh không được hỗ trợ (${mimeType}). Chỉ hỗ trợ JPG, PNG, WEBP.`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Làm sạch chuỗi Base64 nếu có tiền tố data:image/...
    const cleanBase64 = image.includes("base64,")
      ? image.split("base64,")[1].trim()
      : image.trim();

    const geminiPayload = {
      contents: [
        {
          role: "user",
          parts: [
            { text: TIMETABLE_VISION_PROMPT },
            {
              inline_data: {
                mime_type: normalizedMime === "image/jpg" ? "image/jpeg" : normalizedMime,
                data: cleanBase64,
              },
            },
          ],
        },
      ],
      generationConfig: {
        response_mime_type: "application/json",
        response_schema: TIMETABLE_JSON_SCHEMA,
        temperature: 0.1,
      },
    };

    // 7. Gọi Google Gemini REST API (Structured Output) với cơ chế tự động chuyển model khi 503
    let geminiResponse: Response | null = null;
    let activeModel = configuredModel;
    let lastErrorDetail = "";
    let lastStatusCode = 0;

    for (let i = 0; i < candidateModels.length; i++) {
      activeModel = candidateModels[i];
      const geminiUrl = `https://generativelanguage.googleapis.com/${apiVersion}/models/${activeModel}:generateContent?key=${geminiApiKey}`;

      console.log(
        `[Gemini Call Start] Attempt ${i + 1}/${candidateModels.length}. Model: ${activeModel}, API: ${apiVersion}, Payload length: ${cleanBase64.length} chars, MIME: ${normalizedMime}`
      );
      const startTime = Date.now();

      const abortController = new AbortController();
      const timeoutId = setTimeout(() => abortController.abort(), 25000);

      try {
        geminiResponse = await fetch(geminiUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(geminiPayload),
          signal: abortController.signal,
        });
      } catch (fetchErr: any) {
        console.warn(`[Gemini Fetch Error] Model: ${activeModel}, Error: ${fetchErr?.message || fetchErr}`);
        if (i < candidateModels.length - 1) {
          console.log(`[Gemini Failover] Chuyển tiếp sang ${candidateModels[i + 1]} do fetch error.`);
          continue;
        }
        throw fetchErr;
      } finally {
        clearTimeout(timeoutId);
      }

      const durationMs = Date.now() - startTime;
      console.log(
        `[Gemini Call Complete] Model: ${activeModel}, Elapsed: ${durationMs}ms, HTTP Status: ${geminiResponse.status}`
      );

      if (geminiResponse.ok) {
        break; // Gọi thành công!
      }

      lastStatusCode = geminiResponse.status;
      try {
        const errorJson = await geminiResponse.json();
        lastErrorDetail = errorJson?.error?.message || "";
      } catch {
        lastErrorDetail = await geminiResponse.text().catch(() => "");
      }

      console.warn(
        `[Gemini Attempt Failed] Model: ${activeModel}, Status: ${lastStatusCode}, Detail: ${lastErrorDetail}`
      );

      // Nếu là lỗi 503 (High demand) và còn model dự phòng trong danh sách, thử model tiếp theo
      if (lastStatusCode === 503 && i < candidateModels.length - 1) {
        console.log(`[Gemini Failover] Chuyển tiếp sang model dự phòng ${candidateModels[i + 1]} do 503 spike.`);
        continue;
      }

      // Các mã lỗi khác (400, 401, 403, 404) không nên tự ý retry
      break;
    }

    if (!geminiResponse || !geminiResponse.ok) {
      const statusCode = lastStatusCode || 500;
      const sanitizedDetail = lastErrorDetail
        .replace(/key=[^&\s]+/gi, "key=[REDACTED]")
        .trim();

      console.error(
        `[Gemini Final Failure] Model: ${activeModel}, Status: ${statusCode}, Detail: ${sanitizedDetail}`
      );

      if (statusCode === 429) {
        return new Response(
          JSON.stringify({
            success: false,
            error:
              "Hạn mức gọi Gemini AI miễn phí tạm thời bị giới hạn (Quota / Rate Limit Exceeded). Vui lòng thử lại sau 1-2 phút.",
            detail: sanitizedDetail,
          }),
          {
            status: 429,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (statusCode === 401 || statusCode === 403) {
        return new Response(
          JSON.stringify({
            success: false,
            error:
              "Khóa GEMINI_API_KEY không hợp lệ hoặc không có quyền truy cập model được chỉ định.",
            detail: sanitizedDetail,
          }),
          {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (statusCode === 404) {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Model hoặc endpoint Gemini không tồn tại (HTTP 404): ${sanitizedDetail || `Model '${activeModel}' not found in API ${apiVersion}`}.`,
            detail: sanitizedDetail,
            model: activeModel,
            apiVersion,
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (statusCode === 400) {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Yêu cầu ảnh không hợp lệ với Gemini API: ${sanitizedDetail || "Bad Request"}`,
            detail: sanitizedDetail,
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      return new Response(
        JSON.stringify({
          success: false,
          error: `Dịch vụ Gemini AI tạm thời gặp sự cố (HTTP ${statusCode}${sanitizedDetail ? ': ' + sanitizedDetail : ''}). Vui lòng thử lại sau.`,
          detail: sanitizedDetail,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 9. Đọc kết quả văn bản JSON từ phản hồi của Gemini
    const geminiData = await geminiResponse.json();
    const candidateText =
      geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!candidateText || typeof candidateText !== "string") {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Gemini Vision không trả về dữ liệu văn bản từ ảnh.",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 10. Parse JSON và chuẩn hóa dữ liệu
    let rawParsed: any;
    try {
      rawParsed = JSON.parse(candidateText);
    } catch {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Dữ liệu trả về từ Gemini không đúng định dạng JSON.",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 11. Xác thực và tính toán lại số liệu an toàn
    const validatedResult = validateAndNormalizeAiResponse(rawParsed);

    const totalRawClasses = (rawParsed?.weeks || []).reduce(
      (acc: number, w: any) => acc + (w.classes?.length || 0),
      0
    );
    const validatedClasses = (validatedResult.weeks || []).reduce(
      (acc: number, w: any) => acc + (w.classes?.length || 0),
      0
    );

    console.log(
      `[AI Processing Complete] Raw classes: ${totalRawClasses}, Validated classes: ${validatedClasses}, NeedsReview: ${validatedResult.summary?.needsReviewCount || 0}`
    );

    return new Response(JSON.stringify(validatedResult), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    const isTimeout = err?.name === "AbortError";
    const errorMessage = isTimeout
      ? "Quá trình phân tích ảnh bằng Gemini Vision bị quá hạn (Timeout 45s). Vui lòng thử lại với ảnh dung lượng nhỏ hơn."
      : "Đã xảy ra sự cố không mong muốn trong quá trình xử lý Edge Function.";

    return new Response(JSON.stringify({ success: false, error: errorMessage }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
