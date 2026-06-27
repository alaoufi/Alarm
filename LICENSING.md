# تفعيل التطبيق المربوط بالجهاز (Device-bound Activation)

حماية احترافية تعمل **دون إنترنت**: كل جهاز يحتاج رمز تفعيل موقّعًا منك،
والرمز يعمل على ذلك الجهاز فقط. نشر الـAPK لا يفيد أحدًا.

## الإعداد (مرة واحدة)

1. ولّد زوج مفاتيح على جهازك أنت (لا تفعلها في CI):

   ```
   cd mudhakkarati
   dart run tool/license.dart keygen
   ```

2. انسخ سطر `PUBLIC KEY` والصقه مكان `_publicKeyB64` في
   `lib/services/license_service.dart`.

3. **احتفظ بـ `PRIVATE KEY` سرًّا تمامًا** — لا تضعه في الكود أو على GitHub.
   به وحده تُولَّد الرموز؛ تسريبه يكسر الحماية.

> ملاحظة: قبل ضبط المفتاح العام يبقى التطبيق غير مقفول (وضع تطوير).

## تفعيل جهاز مستخدم

1. المستخدم يفتح التطبيق فيظهر **«رقم الجهاز»** ويرسله لك.
2. تولّد له الرمز:

   ```
   dart run tool/license.dart sign <PRIVATE_KEY_B64> <DEVICE_ID>
   ```

3. ترسل له الرمز، فيلصقه في شاشة التفعيل ويعمل التطبيق على جهازه فقط.

## لماذا هذا آمن وعملي

- الرمز توقيع Ed25519 على رقم الجهاز؛ لا يُزوَّر بدون مفتاحك الخاص.
- الرمز مرتبط بجهاز واحد ⇒ عمليًّا «يُستخدم مرة».
- لا خادم ولا إنترنت — يناسب تطبيقًا أوفلاين بالكامل.

## الصيغة الدقيقة (المعادلة)

### كيف يُولّد التطبيق «رقم الجهاز»
```
raw      = ANDROID_ID            (أو identifierForVendor على iOS)
digest   = SHA-256( "mudhakkarati:" + raw )
deviceId = Base32( digest[0..9] )            # 10 بايت ⇒ 16 حرفًا
العرض    = تُجمَّع كل 4 أحرف بشرطة: XXXX-XXXX-XXXX-XXXX
```
أبجدية Base32 (بلا أحرف ملتبسة): `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`

### كيف تُولّد أنت رمز التفعيل
```
n    = رقم الجهاز بأحرف كبيرة بعد حذف المسافات والشرطات
sig  = Ed25519_Sign( PRIVATE_KEY , UTF8(n) )      # توقيع 64 بايت
code = Base64(sig) مع حذف "=" من النهاية
```
الخوارزمية قياسية (RFC 8032) فتعمل بأي لغة. التطبيق يتحقق بنفس المنطق:
يطبّع رقم الجهاز ثم يتحقق من التوقيع بالمفتاح العام المدمج.

### مولّد بديل بلغة بايثون
```python
# pip install pynacl
import base64, sys
from nacl.signing import SigningKey

priv_b64, device_id = sys.argv[1], sys.argv[2]
n = device_id.strip().replace(" ", "").replace("-", "").upper()
sk = SigningKey(base64.b64decode(priv_b64))          # المفتاح الخاص (32 بايت)
sig = sk.sign(n.encode()).signature                  # 64 بايت
print(base64.b64encode(sig).decode().rstrip("="))    # رمز التفعيل
```
تشغيل: `python sign.py <PRIVATE_KEY_B64> <DEVICE_ID>`

