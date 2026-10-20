# Bản Python của Composer trong Sources/VietInput.swift – để kiểm thử logic ghép dấu.
# Giữ logic giống hệt bản Swift; khi sửa một bên phải sửa bên kia.

VOWELS = set("aeiouy")
TONE_TABLE = {
    "a0": "aáàảãạ", "a1": "âấầẩẫậ", "a2": "ăắằẳẵặ",
    "e0": "eéèẻẽẹ", "e1": "êếềểễệ",
    "i0": "iíìỉĩị",
    "o0": "oóòỏõọ", "o1": "ôốồổỗộ", "o2": "ơớờởỡợ",
    "u0": "uúùủũụ", "u2": "ưứừửữự",
    "y0": "yýỳỷỹỵ",
}
DECOMP = {}
for key, forms in TONE_TABLE.items():
    base, mod = key[0], int(key[1])
    for tone, ch in enumerate(forms):
        if tone > 0 or mod > 0:
            DECOMP[ch] = (base, mod, tone)
DECOMP["đ"] = ("d", 1, 0)


class VChar:
    def __init__(self, base, mod=0, upper=False, lone_w=False, literal=False):
        self.base, self.mod, self.upper, self.lone_w, self.literal = base, mod, upper, lone_w, literal


class RawKey:
    """Một phím đã gõ; literal=True nghĩa là chữ thuần, không được biến đổi thêm (sau khi huỷ dấu)."""
    def __init__(self, ch, literal=False):
        self.ch, self.literal = ch, literal


def tone_key(c, method):
    if method == "vni":
        return {"1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "0": 0}.get(c)
    return {"s": 1, "f": 2, "r": 3, "x": 4, "j": 5, "z": 0}.get(c)


def mod_key(c, method):
    if method == "vni":
        return {"6": "circAny", "7": "horn", "8": "breve", "9": "dd"}.get(c)
    return {"a": "circA", "e": "circE", "o": "circO", "w": "hornOrBreve", "d": "dd"}.get(c)


def has_vowel(chars):
    return any(c.base in VOWELS and not c.literal for c in chars)


def last_index(chars, pred):
    for i in range(len(chars) - 1, -1, -1):
        if pred(chars[i]):
            return i
    return None


def apply_mod(chars, m, lower, upper):
    if m in ("circA", "circE", "circO"):
        if not chars or chars[-1].base != lower or chars[-1].literal:
            return False
        if chars[-1].mod == 0:
            chars[-1].mod = 1
            return True
        if chars[-1].mod == 1:
            chars[-1].mod = 0
            return False
        return False
    if m == "circAny":
        i = last_index(chars, lambda c: c.base in "aeo" and not c.literal)
        if i is not None:
            if chars[i].mod == 1:
                chars[i].mod = 0
                return False
            chars[i].mod = 1
            return True
        return False
    if m in ("horn", "breve", "hornOrBreve"):
        if m == "hornOrBreve" and chars and chars[-1].mod == 2 and not chars[-1].literal:
            if chars[-1].lone_w:
                chars.pop()
            else:
                chars[-1].mod = 0
            return False
        targets = {"o", "u"} if m == "horn" else ({"a"} if m == "breve" else {"a", "o", "u"})
        i = last_index(chars, lambda c: c.base in targets and c.mod == 0 and not c.literal)
        if i is not None:
            chars[i].mod = 2
            if chars[i].base == "o" and i > 0 and chars[i - 1].base == "u" and chars[i - 1].mod == 0:
                chars[i - 1].mod = 2
            return True
        if m == "hornOrBreve" and not has_vowel(chars):
            chars.append(VChar("u", 2, upper, True))
            return True
        return False
    if m == "dd":
        if lower == "9":
            i = last_index(chars, lambda c: c.base == "d" and not c.literal)
            if i is not None:
                chars[i].mod = 0 if chars[i].mod == 1 else 1
                return chars[i].mod == 1
            return False
        if not chars or chars[-1].base != "d" or chars[-1].literal:
            return False
        if chars[-1].mod == 0:
            chars[-1].mod = 1
            return True
        chars[-1].mod = 0
        return False


def tone_index(chars, modern):
    last_v = last_index(chars, lambda c: c.base in VOWELS)
    if last_v is None:
        return None
    start = last_v
    while start > 0 and chars[start - 1].base in VOWELS:
        start -= 1
    if start < last_v:
        if chars[start].base == "u" and start > 0 and chars[start - 1].base == "q":
            start += 1
        elif chars[start].base == "i" and start > 0 and chars[start - 1].base == "g":
            start += 1
    cluster = list(range(start, last_v + 1))
    if len(cluster) == 1:
        return cluster[0]
    for i in reversed(cluster):
        if chars[i].mod != 0:
            return i
    has_final = last_v < len(chars) - 1
    if len(cluster) >= 3:
        return cluster[1]
    if has_final:
        return cluster[1]
    if modern:
        pair = chars[cluster[0]].base + chars[cluster[1]].base
        if pair in ("oa", "oe", "uy"):
            return cluster[1]
    return cluster[0]


def render(chars, tone, modern):
    out = ""
    tone_at = None if tone == 0 else tone_index(chars, modern)
    for i, c in enumerate(chars):
        if c.base in VOWELS:
            forms = TONE_TABLE.get(c.base + str(c.mod)) or TONE_TABLE[c.base + "0"]
            ch = forms[tone if tone_at == i else 0]
        elif c.base == "d" and c.mod == 1:
            ch = "đ"
        else:
            ch = c.base
        out += ch.upper() if c.upper else ch
    return out


INITIALS = {"", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh", "nh",
            "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"}
FINALS = {"", "c", "ch", "m", "n", "ng", "nh", "p", "t"}
STOP_FINALS = {"c", "ch", "p", "t"}
CLUSTERS = {
    "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
    "ai", "ao", "au", "ay", "âu", "ây", "eo", "êu", "ia", "iê", "iu", "oa", "oă", "oe", "oi", "ôi", "ơi", "oo",
    "ua", "uâ", "uê", "ui", "uô", "uơ", "uy", "ưa", "ưi", "ươ", "ưu", "ya", "yê", "uă",
    "iêu", "oai", "oay", "oeo", "uây", "uôi", "uya", "uyê", "uyu", "ươi", "ươu", "yêu", "uao",
}


def letter(c):
    if c.base in VOWELS:
        return TONE_TABLE[c.base + str(c.mod)][0] if (c.base + str(c.mod)) in TONE_TABLE else c.base
    return "đ" if (c.base == "d" and c.mod == 1) else c.base


def is_valid_syllable(chars, tone):
    """Kiểm tra chính tả đơn giản: phụ âm đầu + nguyên âm + phụ âm cuối phải hợp lệ."""
    if not chars:
        return True
    letters = [letter(c) for c in chars]
    if any(l not in "aăâeêioôơuưyđbcdfghjklmnpqrstvwxz" for l in letters):
        return False
    i = 0
    while i < len(letters) and letters[i] not in "aăâeêioôơuưy":
        i += 1
    initial = "".join(letters[:i])
    j = i
    while j < len(letters) and letters[j] in "aăâeêioôơuưy":
        j += 1
    cluster = letters[i:j]
    final = "".join(letters[j:])
    if initial == "q" and cluster and cluster[0] == "u":
        initial, cluster = "qu", cluster[1:]
    elif initial == "g" and len(cluster) > 1 and cluster[0] == "i":
        initial, cluster = "gi", cluster[1:]
    if initial not in INITIALS or final not in FINALS:
        return False
    if not cluster:
        return initial in ("gi", "qu")   # "gi", "qu" đang gõ dở
    if "".join(cluster) not in CLUSTERS:
        return False
    if final in STOP_FINALS and tone in (2, 3, 4):
        return False
    return True


def compose(raw, method="telex", modern=False, spellcheck=True):
    """raw: list[RawKey] hoặc str. Trả về (chuỗi hiển thị, phím cuối có huỷ dấu không)."""
    keys = [k if isinstance(k, RawKey) else RawKey(k) for k in raw]
    chars, tone = [], 0
    reverted = False
    for idx, key in enumerate(keys):
        k = key.ch
        is_last = idx == len(keys) - 1
        if ord(k) > 127 or key.literal:
            d = DECOMP.get(k.lower()) if ord(k) > 127 else None
            if d:
                chars.append(VChar(d[0], d[1], k.isupper(), literal=key.literal))
                if d[2]:
                    tone = d[2]
            else:
                chars.append(VChar(k.lower(), 0, k.isupper(), literal=key.literal))
            continue
        lower, upper = k.lower(), k.isupper()
        handled = False
        t = tone_key(lower, method)
        if t is not None and has_vowel(chars):
            if t == 0:
                if tone != 0:
                    tone, handled = 0, True
            elif tone == t:
                tone = 0
                if is_last:
                    reverted = True
            else:
                tone, handled = t, True
        if not handled:
            m = mod_key(lower, method)
            if m:
                before = [(c.base, c.mod) for c in chars]
                handled = apply_mod(chars, m, lower, upper)
                after = [(c.base, c.mod) for c in chars]
                if not handled and is_last and before != after:
                    reverted = True
        if not handled:
            chars.append(VChar(lower, 0, upper))
    if spellcheck and not reverted and not is_valid_syllable(chars, tone):
        return "".join(k.ch for k in keys), reverted
    return render(chars, tone, modern), reverted


# Mô phỏng VietInput.handle: gõ từng phím, trả về chuỗi hiển thị cuối cùng
def type_word(keys, method="telex", modern=False):
    raw, displayed = [], ""
    for k in keys:
        if k == "\b":
            if displayed:
                displayed = displayed[:-1]
                raw = [RawKey(c) for c in displayed]
            continue
        candidate = raw + [RawKey(k)]
        new, reverted = compose(candidate, method, modern)
        # Huỷ dấu: chuỗi hiển thị trở thành chữ thuần, không khôi phục phím cũ nữa
        raw = [RawKey(c, literal=True) for c in new] if reverted else candidate
        displayed = new
    return displayed


if __name__ == "__main__":
    cases = [
        ("xoas", "xóa"), ("traanf", "trần"), ("tieesng", "tiếng"), ("vieejt", "việt"),
        ("ddaau", "đâu"), ("ddwowngf", "đường"), ("nguwowif", "người"), ("thuowng", "thương"),
        ("hoa", "hoa"), ("hoas", "hóa"), ("thuys", "thúy"), ("quas", "quá"), ("gias", "giá"),
        ("toans", "toán"), ("ngoaif", "ngoài"), ("khoer", "khỏe"), ("muwa", "mưa"), ("muwas", "mứa"),
        ("cuar", "của"), ("ruowuj", "rượu"), ("yeeu", "yêu"), ("tuyeejt", "tuyệt"), ("ddieen", "điên"),
        ("ass", "as"), ("aaa", "aa"), ("ddd", "dd"), ("casch", "cách"), ("laptop", "laptop"),
        ("Vieejt", "Việt"), ("VIEEJT", "VIỆT"), ("Traanf", "Trần"), ("chuwa", "chưa"), ("ddooi", "đôi"),
        ("bieets", "biết"), ("quoocs", "quốc"), ("nhuwngx", "những"), ("mootj", "một"), ("hocj", "học"),
        ("tooi", "tôi"), ("xin", "xin"), ("chaof", "chào"), ("uwowts", "ướt"),
        ("quyeens", "quyến"), ("thuowngf", "thường"), ("files", "files"), ("and", "and"), ("ass", "as"),
        ("gif", "gì"), ("giuwx", "giữ"), ("gieeng", "giêng"), ("ngoawnf", "ngoằn"), ("ddaams", "đấm"),
        ("thuyeetj", "thuyệt"), ("khoong", "không"), ("nghieeng", "nghiêng"), ("test", "tét"),
        ("ddeens", "đến"), ("gooogle", "google"), ("google", "google"), ("gooo", "goo"), ("gooof", "goof"),
        ("tooo", "too"), ("ddd", "dd"), ("dddd", "ddd"), ("wwwf", "wwf"), ("ngoanf", "ngoàn"), ("rooif", "rồi"), ("owi", "ơi"), ("uwf", "ừ"), ("mwowif", "mười"),
    ]
    bad = 0
    for keys, want in cases:
        got = type_word(keys)
        if got != want:
            bad += 1
            print(f"FAIL {keys!r}: got {got!r}, want {want!r}")
    # Backspace: "trần" + ⌫ → "trầ" ; rồi gõ n → "trần"
    assert type_word("traanf\b") == "trầ", type_word("traanf\b")
    assert type_word("traanf\bn") == "trần", type_word("traanf\bn")
    assert type_word("traa\b") == "tr"
    assert type_word("xoas\b") == "xó"
    print("VNI:", type_word("tie61ng", "vni"), type_word("d9u7o72ng", "vni"), type_word("ho5c", "vni"))
    print(f"{len(cases) - bad}/{len(cases)} ok")
