# التفعيل العالميّ — مستند واحد لأيّ مطوّر / أيّ لغة

أرسل هذا الملفّ كما هو لأيّ مطوّر تطبيق (Flutter / ويب / أندرويد أصليّ). **الثوابت
والخوارزميّة موحّدة في كل اللغات**؛ المطوّر يأخذ قسم لغته فقط. مفتاح عالميّ واحد
يفعّل كل التطبيقات، ويعمل **دون إنترنت**. المطوّر يحتاج المفتاح **العامّ** فقط.

---

## 1) الثوابت العالميّة (متطابقة في كل اللغات — لا تتغيّر)
| العنصر | القيمة |
|---|---|
| المفتاح العامّ (Base64) | `0JXPjbbPjczfYbYxl+jy1vOVcsEJT+CPbUIQgXNCStU=` |
| بادئة الرسالة | `UNIV1` |
| ملح معرّف الجهاز | `alaoufi:` |
| التعمية | Ed25519 (RFC 8032) |
| ترميز الكود | Base32 مخصّص: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` |

## 2) الخوارزميّة (لغة محايدة)
```
رقم الجهاز:
  raw      = معرّف عتاد الجهاز (ANDROID_ID / identifierForVendor / عشوائي مخزَّن للويب)
  deviceId = base32( SHA256("alaoufi:" + raw)[0..10) )        // 16 حرفًا

التحقّق من الكود (بالمفتاح العامّ فقط):
  pkt = base32_decode( تطبيع(code) )   // تطبيع: أحرف كبيرة + احذف ما ليس [A-Z0-9]
  if len(pkt) != 66: فشل
  duration = (pkt[0] << 8) | pkt[1]    // أيام، 0 = دائم
  sig      = pkt[2..66)                // 64 بايت
  msg      = "UNIV1|" + deviceId + "|" + duration
  ok       = Ed25519_verify(msg, sig, PUBLIC_KEY)

المدّة (تُفحص عند كل فتح):
  effNow = max(now, lastSeen)          // حارس: إرجاع الساعة لا يمدّد المدّة
  duration==0 ⇒ دائم
  effNow < activatedAt + duration*86400000 ⇒ مفعّل، وإلّا ⇒ منتهٍ
```

---

## 3) Dart (Flutter)
استبدل `lib/services/license_service.dart` بالملفّ الجاهز المرفق، أو اضبط الثوابت:
```dart
static const String _publicKeyB64 = '0JXPjbbPjczfYbYxl+jy1vOVcsEJT+CPbUIQgXNCStU=';
static const String _msgPrefix    = 'UNIV1';
// رقم الجهاز:  crypto.sha256.convert(utf8.encode('alaoufi:$raw'))
```
الحزم: `cryptography`, `crypto`, `android_id`, `device_info_plus`, `flutter_secure_storage`, `path_provider`.

## 4) JavaScript / الويب
```bash
npm i tweetnacl
```
```js
import nacl from 'tweetnacl';
const B32='ABCDEFGHJKLMNPQRSTUVWXYZ23456789', PREFIX='UNIV1';
const PUBKEY_B64='0JXPjbbPjczfYbYxl+jy1vOVcsEJT+CPbUIQgXNCStU=';
const norm=s=>s.toUpperCase().replace(/[^A-Z0-9]/g,'');
const enc=s=>new TextEncoder().encode(s);
function b64(b){const x=atob(b),o=new Uint8Array(x.length);for(let i=0;i<x.length;i++)o[i]=x.charCodeAt(i);return o;}
function b32d(str){let bits=0,v=0;const o=[];for(const c of str){const i=B32.indexOf(c);if(i<0)continue;v=(v<<5)|i;bits+=5;if(bits>=8){o.push((v>>>(bits-8))&255);bits-=8;}v&=(1<<bits)-1;}return Uint8Array.from(o);}
function verifyCode(code, deviceId){
  const pkt=b32d(norm(code)); if(pkt.length!==66) return null;
  const dur=(pkt[0]<<8)|pkt[1], sig=pkt.slice(2);
  const msg=enc(`${PREFIX}|${norm(deviceId)}|${dur}`);
  return nacl.sign.detached.verify(msg,sig,b64(PUBKEY_B64))?dur:null;
}
// deviceId: SHA-256("alaoufi:"+raw) ثم base32 لأوّل 10 بايت (انظر license_universal.js المرفق).
```

## 5) Kotlin (أندرويد أصليّ)
```kotlin
// build.gradle:  implementation("org.bouncycastle:bcprov-jdk15on:1.70")
import android.util.Base64
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.MessageDigest

object UniversalLicense {
  private const val PUBKEY_B64 = "0JXPjbbPjczfYbYxl+jy1vOVcsEJT+CPbUIQgXNCStU="
  private const val PREFIX = "UNIV1"
  private const val SALT = "alaoufi:"
  private const val B32 = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  private fun norm(s: String) = s.uppercase().replace(Regex("[^A-Z0-9]"), "")

  fun base32(bytes: ByteArray): String {
    var bits = 0; var v = 0; val sb = StringBuilder()
    for (b in bytes) { v = (v shl 8) or (b.toInt() and 0xff); bits += 8
      while (bits >= 5) { sb.append(B32[(v shr (bits - 5)) and 31]); bits -= 5 } ; v = v and ((1 shl bits) - 1) }
    if (bits > 0) sb.append(B32[(v shl (5 - bits)) and 31]); return sb.toString()
  }
  private fun base32Decode(s: String): ByteArray {
    var bits = 0; var v = 0; val out = ArrayList<Byte>()
    for (c in s) { val i = B32.indexOf(c); if (i < 0) continue
      v = (v shl 5) or i; bits += 5
      if (bits >= 8) { out.add(((v shr (bits - 8)) and 0xff).toByte()); bits -= 8 } ; v = v and ((1 shl bits) - 1) }
    return out.toByteArray()
  }
  fun deviceId(raw: String): String {
    val d = MessageDigest.getInstance("SHA-256").digest((SALT + raw).toByteArray(Charsets.UTF_8))
    return base32(d.copyOfRange(0, 10))
  }
  /** يعيد المدّة (0 = دائم) أو null عند الفشل. */
  fun verify(code: String, deviceId: String): Int? {
    val pkt = base32Decode(norm(code)); if (pkt.size != 66) return null
    val dur = ((pkt[0].toInt() and 0xff) shl 8) or (pkt[1].toInt() and 0xff)
    val sig = pkt.copyOfRange(2, 66)
    val msg = "$PREFIX|${norm(deviceId)}|$dur".toByteArray(Charsets.UTF_8)
    val pub = Ed25519PublicKeyParameters(Base64.decode(PUBKEY_B64, Base64.DEFAULT), 0)
    val signer = Ed25519Signer().apply { init(false, pub); update(msg, 0, msg.size) }
    return if (signer.verifySignature(sig)) dur else null
  }
}
```

---

## 6) متجهات اختبار (للتأكّد من تطابق أي تنفيذ)
بادئة `UNIV1`، رقم الجهاز `TESTDEVICE234567` (بلا شرطات):
| المدّة | الكود (بلا شرطات) |
|---|---|
| 0 (دائم) | `AAANSJ2UELQ398JB5X4FPSV9DWUW3XSRP367RBVF9ASD7URBN55UTUBRMHWNYEQTL6HQLVS43XA5B3K7QK2ZU7FF4GX8PJB93BE4CKB2AJ` |
| 30 | `AARLNZUCVGUA827D3FUBNPHB9ESX6KZX4EWUEM7NX7LU2CJ5XX4JPZSBUPAWUDNKH2TAP2P7992LQ99UNV9HP55BME68X8EM8FBU69UBAJ` |

`verify(الكود, "TESTDEVICE234567")` يجب أن يعيد المدّة (0 أو 30)، وأيّ جهاز آخر ⇒ null.

## 7) بعد التعديل
أعِد بناء التطبيق ونشره وتثبيت النسخة الجديدة. ثم: المولّد ← «عام» ← رقم الجهاز ← كود ← يعمل.
**المستخدمون المفعَّلون حاليًّا لا يتأثّرون** (التفعيل المخزَّن لا يُعاد التحقّق منه).
