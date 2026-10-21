# 12 — Israeli and US menu lexicon: where allergens hide

**Status: desk research, not clinical review.** Everything below was gathered
from published web sources (Hebrew and English) on 2026-10-11 by an agent with
search access only. No dietitian, allergist or lawyer has reviewed it. Every
claim carries a URL; sources are graded at the end (**[strong]** official,
clinical or peer-reviewed; **[medium]** national press, hospital or patient
association; **[weak]** blogs, recipe sites, forums, vendor pages). The agent's
environment could not open any page directly (every fetch failed at DNS), so
all quotations come from search-result excerpts of the cited pages, not from
reading the pages in full. Treat exact numbers as "reported", and re-read the
primary page before putting any figure in the product.

**Could not verify** (named again in the relevant sections):

- Whether the Ministry of Health's 2028 allergen rule reaches restaurant
  menus (every source found says it covers pre-packaged food only;
  re-checked 2026-10-19, §4.2: still prepacked only, and a search excerpt
  of the Ministry guide names 1 Jan 2032 for non-prepacked food).
- Whether Wolt Israel or 10bis carry a *structured* per-dish allergen or
  dietary field. Both show venue-level tags and restaurant-written text; no
  official documentation of a dish-level schema was found.
- A current, official Israeli celiac prevalence number (sources range 0.5–2%).
- A measured (not genotype-based) lactose-intolerance rate for Israel.
- The claim that sesame is "second only to cow's milk" as a cause of
  anaphylaxis in Israel: the 2002 abstract ranks egg, milk, then sesame.
- Whether the "allergy-aware restaurant" seal the celiac association announced
  in 2017 was ever launched.

How to use this file: the Hebrew spellings in §1 are the strings a menu parser
should match; §2 tells the app which menu words carry allergen meaning and
which do not; §3 justifies the priority order for Israel; §4 is the regulatory
and platform picture; §5 is the US cuisine supplement.

---

## 1. Israeli dishes and menu items that hide each allergen

Hebrew menu spellings vary. Where a word has common variants (ג'חנון / ג׳חנון,
כובאנה / קובנה, מלאווח / מלווח, טחינה / טחינא) the parser should accept all.
Hebrew `\b` does not work in Dart (see `CLAUDE.md`), so the same lookaround
rules used for the keto vocabulary apply here.

### 1.1 Sesame — שומשום (also סומסום, שומשומין; sesame oil שמן שומשום)

Why it leads the list: sesame is the signature Israeli allergen (§3.1).

| Menu item (Hebrew) | English | Where the sesame is | Source |
|---|---|---|---|
| טחינה / טחינא | tahini | 100% ground sesame; the base of most Israeli sauces and salads | allergy.org.il lists טחינה, חומוס, חלבה, מאפים, רטבים as sesame foods: https://allergy.org.il/אלרגיה-לשומשום/ **[medium]** |
| חומוס (ממרח) | hummus spread | made with tahini, so sesame even when the menu names only chickpeas | same, plus Dubdevan children's guide: https://www.rdm.co.il/food-allergy/ **[weak]** |
| חלבה | halva | sesame-based confection — **not** a milk product despite the spelling similarity to חלב (milk) | https://allergy.org.il/אלרגיה-לשומשום/ **[medium]** |
| בורקס | bourekas | sesame scattered on the egg-washed top ("מברישים בביצה טרופה ומפזרים מעל שומשום") | https://www.hidabroot.org/article/1226396 **[weak]** |
| פלאפל | falafel | sesame is in some batters ("1 כף שומשום" in HaKosem's published recipe) and used as a coating; served with tahini. *Checked 2026-10-19:* "many" became "some" — one recipe is the only batter source, though Virginia Tech lists falafel as a food that may contain sesame and the FSA recalled a falafel mix for undeclared sesame (https://pubs.ext.vt.edu/FST/fst-449/fst-449.html **[S]** ; https://www.food.gov.uk/news-alerts/alert/fsa-aa-60-2025 **[S]**) | https://www.mako.co.il/food-weekend/falafel-hakosem/Article-24b9ad2f82a7351006.htm ; https://taimeta.co.il/falafel-making-spoon-recipe/ **[weak]** |
| סביח | sabich | served with tahini and often amba; egg too (see 1.6) | https://www.bishulim.co.il/מתכון/סביח-חצילים-וביצה-קשה **[weak]** |
| סלט חצילים (בטחינה) | eggplant salad | one of two common bases is tahini (the other is mayonnaise, see 1.6); menus often omit which | https://www.krutit.co.il/סלט-חצילים-בטחינה-ומיונז/ **[weak]** |
| לחמנייה / פיתה / בייגלה / בייגל ירושלמי | rolls, pita, pretzels, Jerusalem bagel | sesame topping; Dubdevan tells sesame-allergic children to avoid לחמנייה | https://www.rdm.co.il/food-allergy/ **[weak]** |
| ג'חנון / מלאווח / כובאנה | Yemenite pastries | not sesame foods themselves, but commonly served with tahini-based or sesame-garnished sides; parse the accompaniments | (inference from the dishes above; no direct source) |
| סלטים עם שומשום קלוי, רוטב שומשום, "אסייתי" | roasted-sesame garnish, sesame dressings | sesame oil and seeds in Asian-style dishes on Israeli menus | FARE/Spokin on Asian cuisine, §5 |
| במבה במילוי | filled Bamba variants | Osem lists שומשום among the allergens of the nougat- and cookie-cream-filled Bamba | https://www.osem-nestle.co.il/brands/במבה/חטיף-במבה-במילוי-קרם-נוגט-אריזה-גדולה **[strong, manufacturer]** |

Trap for the parser: **חלבה ≠ חלב**. A naive substring match on "חלב" (milk)
will hit "חלבה" (halva, sesame) and "חלבי" (dairy, §2). Match on whole
tokens.

### 1.2 Peanuts (בוטנים) versus tree nuts (אגוזים)

| Term on menus | Means | Note | Source |
|---|---|---|---|
| בוטנים, אגוזי אדמה | peanuts | botanically a legume, not a nut; Hebrew Wikipedia: "אלרגיות לאגוזי עץ נבדלות מאלרגיה לבוטנים (אגוזי אדמה), מכיוון שבוטנים הם קטניות" | https://he.wikipedia.org/wiki/בוטן ; https://he.wikipedia.org/wiki/אלרגיה_לאגוזים **[medium]** |
| אגוזים (generic) | "nuts" — on an Israeli menu usually tree nuts, but can be used loosely | treat generic אגוזים as *tree nuts, peanut status unknown* and ask | Dr Kobi Sadeh: 20–40% of tree-nut-allergic people also react to peanut: https://allergynet.co.il/אלרגיה-למזון/אלרגיה-לאגוזים/ **[medium]** |
| שקדים | almonds (tree nut) | common in Moroccan/Tripolitan dishes, pastries, "שקדי מרק" is a *soup crouton* (wheat, not almond) | (naming note; no allergen source needed) |
| פיסטוק / פיסטוקים | pistachio | halva, baklava, kadaif, ice cream | (menu vocabulary) |
| אגוזי מלך | walnuts | in חרוסת, salads, cakes | (menu vocabulary) |
| צנוברים | pine nuts | on hummus, in rice and pastries | (menu vocabulary) |
| אגוזי לוז | hazelnuts | spreads, filled Bamba | Osem Bamba nougat: https://www.osem-nestle.co.il/brands/במבה/חטיף-במבה-במילוי-קרם-נוגט-אריזה-גדולה **[strong]** |
| במבה | Bamba | classic Bamba is **54% ground peanuts**; Osem lists allergens as peanuts and soy. *Checked 2026-10-19:* export retail listings print 50–54% peanut and give soy only as "may contain" (https://www.woolworths.com.au/shop/productdetails/131914/osem-snacks-bamba-with-peanuts ; https://stopandshop.com/groceries/snacks/chips/more-chip-varieties/osem-bamba-peanut-snack-7-oz-bag.html **[weak, retailer]**) | https://www.osem-nestle.co.il/brands/במבה/חטיף-במבה-קלאסית **[strong, manufacturer]** |
| "Arachis hypogaea" | peanut (Latin, on labels and medicines) | | http://ek.meydalle.info/kalfon212.htm **[weak]** |

Israeli allergy guidance is to avoid *all* nuts until an allergist separates
them: "כאשר מתגלה אלרגיה לסוג אחד של אגוז יש להמנע מכל האגוזים עד לברור אצל
אלרגולוג" (Yahel, https://www.allergyisrael.org.il/אלרגנים-נפוצים/ **[medium]**).
Product design implication: let the user pick "peanut", "tree nuts" or "all
nuts" as separate profiles, and treat a bare אגוזים as a hit for both until
the dish text names the nut.

### 1.3 Legumes — קטניות (chickpeas, lentils, fava, peas, soy, lupin, fenugreek)

The Israeli allergy association's legume list: "בוטנים, סויה, תורמוס, שעועית
ירוקה, אפונה ירוקה וחילבה", plus "חומוס, עדשים, שעועית וקטניות יבשות אחרות"
(https://allergy.org.il/אלרגיה-קטניות/ **[medium]**). A French series cited in
Hebrew press found peanut-allergic children were sensitised to fenugreek
(66%), lentils (42%), soy (40%) and lupin (34%)
(https://www.e-med.co.il/indications/pediatric-nutrition/2022/10/12/544113 **[medium]**).

| Menu item | Legume | Source |
|---|---|---|
| חומוס, גרגרי חומוס (in salads, on top of hummus plates, in משאוושה) | chickpea | allergy.org.il as above |
| פלאפל | chickpea; some versions fava (פול ירוק) or a mix; chickpea flour (קמח חומוס) in batters | https://he.wikipedia.org/wiki/פלאפל ; https://gilacooking.co.il/green-fava-falafel-recipe/ **[weak]** |
| פול, פול מדמס | fava beans | (menu vocabulary) |
| מג'דרה | rice with lentils | lentils are the defining ingredient; no single source found that labels it an allergen risk — inferred from the legume list |
| עדשים, מרק עדשים, סלט עדשים | lentils | allergy.org.il |
| סביח | often served with chickpeas/hummus in the pita | https://www.10dakot.co.il/recipe/סביח/ **[weak]** |
| שעועית לבנה ברוטב עגבניות, שעועית ירוקה | beans | allergy.org.il |
| אפונה | peas | allergy.org.il |
| חילבה | fenugreek — the Yemenite condiment hilbeh; served with jachnun, malawach, kubaneh, soup | allergy.org.il list; e-med on cross-sensitisation |
| תורמוס | lupin | both a street snack (pickled) and a flour in some gluten-free products; lupin is on the EU/Israeli 14-allergen list (§4.1) |
| סויה, טופו, אדממה, רוטב סויה, מיסו | soy | see 1.11 |
| ציפוי שניצל | one Hebrew recipe forum says lentil flour appears in some schnitzel coatings | https://selected-recipes.com/q-41/ **[weak — single forum answer]** |

One Hebrew allergy site also notes that a legume-allergic person may react to
cooking vapours ("אדי הבישול של קטניות";
https://www.focus.co.il/page/קטניות-ללא-תהיות **[weak]**). Not actionable
for a menu parser, but relevant copy for a hummus bar warning.

### 1.4 Gluten — גלוטן (wheat חיטה, barley שעורה, rye שיפון, spelt כוסמין)

Israeli clinical guidance (Sheba, Maccabi, Shaare Zedek) and the celiac rights
organisation list the obvious breads and these less obvious Israeli items:

| Menu item | Why | Source |
|---|---|---|
| פיתה, לאפה, חלה, בגט, לחמנייה | wheat bread | https://www.maccabi4u.co.il/maccabi_circles/healthy-and-tasty/celiac_disease/ **[medium]** |
| קוסקוס | wheat semolina pasta, not a grain | Maccabi list ("פסטה, פיצה, קוסקוס, אטריות") **[medium]** |
| ג'חנון, מלאווח, כובאנה, בורקס, סמבוסק, מאפים | wheat-dough pastries | Maccabi list names ג'חנון ובורקסים; Hebrew Wikipedia: jachnun is white flour and margarine https://he.wikipedia.org/wiki/ג'חנון **[medium]** |
| פתיתים ("Israeli couscous", "ptitim") | toasted wheat pasta; Osem also sells a **rice** version, so the word alone is ambiguous | https://www.osem-nestle.co.il/brands/אסם/פתיתים-ותוספות/פתיתים-אפויים-אסם-אורז **[strong, manufacturer]** |
| בורגול | cracked wheat (in tabbouleh, kubbeh) | (standard; no Israeli source found — flag) |
| קובה, קובה סולת, קובה בורגול | semolina/bulgur shells | (standard; flag) |
| שניצל, קציצות, קבב מעובד | bread-crumb or flour coating / binder; Shaare Zedek lists "קציצות, שניצלים" among foods to check | https://www.szmc.org.il/departments/wilf-childrens-hospital/hamachon-legastro-yeladim-vetzuna/tzuna-vebeayot-sigsug-beyeladim/dgeshim-tzunatieim/ **[medium]** |
| שקדי מרק, קרוטונים | wheat croutons despite the "almond" name | (naming note) |
| רוטב סויה | wheat is a standard ingredient; Sheba: forbidden "אלא אם קיבל אישור מהיצרן"; even some "tamari" sold in Israel lists חיטה | https://www.sheba.co.il/general/nutrition-guides/nutrition-for-celiac **[strong]** ; https://derech-hatavlinim.co.il/product/רוטב-סויה-תמרי-1-ליטר/ **[weak]** |
| פריכיות | rice cakes are usually gluten-free, but flavoured ones can carry wheat-based soy sauce ("רוטב סויה 3.12% (פולי סויה מלח חיטה מכיל גלוטן)") | https://shkedionet.co.il/product/פריכיות-אורז-בצ'ילי/ **[weak]** ; permitted-list entry at https://www.leumit.co.il/nutrition/celiac-nutrition-without-gluten/ **[medium]** |
| רטבים, נקניקים, תחליפי בשר, תבלינים | hidden gluten in processed items | https://www.foodsdictionary.co.il/articles/1519 **[weak]** ; https://barili.biz/2019/12/05/מותר-ואסור-תזונה-ללא-גלוטן/ **[weak]** |
| בירה | barley | (standard) |
| "קמח" in any dish line | flour; note "קמח חומוס" and "קמח אורז" are gluten-free | (vocabulary) |

Restaurant practice: Aroma's own disclosure says every dish may carry cross
contact and that gluten is present in branch kitchens
(https://www.aroma.co.il/מידע-תזונתי-ואזהרות/ **[medium]**); McDonald's
Israel says its restaurant environment contains gluten and it cannot claim
nut-free status
(https://www.mcdonalds.co.il/מהפיכת_התזונה/מידע_בדבר_אלרגנים **[medium]**).

### 1.5 Milk and lactose — חלב / לקטוז

| Menu word | What it is | Source |
|---|---|---|
| לאבנה, גבינה צפתית, בולגרית, פטה, מוצרלה, קוטג', גבינה לבנה, ריקוטה, פרמזן, גאודה | cheeses (all milk) | bourekas-filling recipes list צפתית, פטה, גאודה, מוצרלה: https://foody.co.il/foody_recipe/בורקס-במלית-גבינה-וזיתים/ **[weak]** |
| שמנת, שמנת מתוקה, שמנת חמוצה, חמאה, סמנה (Yemenite clarified butter) | cream, butter, ghee | jachnun was traditionally made with סאמנה — clarified butter — before margarine replaced it in Israel: https://he.wikipedia.org/wiki/ג'חנון **[medium]** |
| ג'חנון, מלאווח, כובאנה | may be butter (dairy) **or** margarine (pareve) — the menu seldom says which | kubaneh recipes use butter, samneh or margarine: https://he.wikipedia.org/wiki/כובאנה **[medium]** ; malawach "with margarine for those sensitive to dairy": https://momflavours.co.il/melt-in-your-mouth-malawach-recipe/ **[weak]** |
| בורקס גבינה | cheese filling; even potato bourekas may contain cheese/egg | https://www.matkonzikaron.co.il/dairy-recipe/בורקס-גבינה-ותפוח-אדמה **[weak]** |
| חלבה | **sesame, not milk** — see 1.1 | |
| "חלבי" | dairy kosher category — see §2 | |
| "פרווה" / "טבעוני" | **does not guarantee milk-free** — see §2 | |
| "ללא תוספת סוכר" on a dairy dessert | still contains lactose: "מוצר חלב ללא תוספת סוכר עדיין יכול להכיל לקטוז" | https://dietmaya.substack.com/p/e5f **[weak]** |
| "ללא לקטוז" | lactose-free, **not** milk-protein-free (milk-allergic users must still avoid) | (standard; see Yahel's rule that milk allergy must rely on ingredient lists only: https://www.allergyisrael.org.il/אלרגנים-נפוצים/ **[medium]**) |

### 1.6 Eggs — ביצים

| Menu item | Egg source | Source |
|---|---|---|
| שקשוקה | eggs are the dish | (definitional) |
| סביח | hard-boiled egg is a standard component ("חציל מטוגן, ביצה קשה, טחינה ועמבה") | https://www.bishulim.co.il/מתכון/סביח-חצילים-וביצה-קשה **[weak]** |
| מיונז, איולי, רוטב אלף האיים, סלט חצילים במיונז, סלט כרוב במיונז, סלט ביצים | mayonnaise-based | https://www.mako.co.il/food-holiday-recipes/passover/Recipe-e693fe140dad681026.htm **[weak]** ; Beok: eggs hide in "פסטה, רטבים, מיונז, מרקים מסוימים, שניצלים מוכנים, קציצות" https://blog.beok.co.il/article/15482/ **[medium]** |
| שניצל, קציצות | egg in the batter; one source reports mayonnaise added to schnitzel batter and meat patties in industrial kitchens | https://selected-recipes.com/q-41/ **[weak]** |
| חלה, בורקס (egg wash), עוגות, מרנג, פסטה טרייה | baked goods | Beok list above |
| ביצה קשה on הומוס / פול | optional topping often on by default | (menu vocabulary) |
| Label names: אלבומין, גלובולין, ליזוזים, לציטין (ממקור ביצה) | egg derivatives | https://mayatzur.com/2020/03/11/השמות-השונים-שאלרגנים-יכולים-להופיע-ע/ **[weak]** |

### 1.7 Fish and shellfish — דגים / פירות ים

| Menu item | Note | Source |
|---|---|---|
| חריימה | Tripolitan/Tunisian fish in red sauce; the classic is fish, but there are shrimp-and-calamari "חריימה פירות ים" versions | https://www.hashulchan.co.il/topic/חריימה/ **[weak]** ; https://www.haaretz.co.il/food/recipes/2022-09-18/ty-article-recipe/00000183-50e8-d6c6-afe7-f7e8ea2c0000 **[medium]** |
| "פירות ים" | shellfish; **absence of a kosher certificate is not an allergen signal, but presence of one means no shellfish** (shrimp is non-kosher in every form) | https://sweetscent.co.il/shrimp-kosher-halacha/ **[weak]** ; https://www.hidabroot.org/question/17740 **[weak]** |
| שרימפס, קלמרי, מולים, סרטנים, צדפות | shellfish/molluscs | (vocabulary) |
| רוטב דגים, אנשובי (in Caesar dressing), רוטב צדפות, חמאת שרימפס, משחת שרימפס | hidden fish/shellfish in sauces — Israeli Asian and Italian menus | ASCIA shellfish guide: fish sauce, prawn crackers, oyster sauce https://www.allergy.org.au/images/pc/ASCIA_PC_Dietary_Guide_Shellfish_Alllergy_2023.pdf **[strong]** |
| קציצות דגים, גפילטע פיש | fish | (vocabulary) |

### 1.8 Mustard — חרדל

Mustard is an IgE allergy to the seed's storage proteins
(https://he.wikipedia.org/wiki/אלרגיה_לחרדל **[medium]**). It appears in
Israeli menus as חרדל, חרדל דיז'ון, "רוטב חרדל-דבש", in vinaigrettes
(ויניגרט), in the classic סלט חצילים במיונז recipe ("מיץ לימון, מיונז, חרדל,
שום": https://www.mako.co.il/food-holiday-recipes/passover/Recipe-e693fe140dad681026.htm
**[weak]**), in Caesar dressing (a US recipe label lists "Milk, Anchovies,
Egg, Mustard": https://www.hellofresh.ca/recipes/classic-turkey-meatballs-6829eb1d99bb603b9b4386e6
**[weak]**), and as seed in curry pastes and marinades
(https://www.mako.co.il/health-illnesses-and-medicines/illnesses/Article-6ca7db1f3dfac51006.htm
**[medium]**). It is on the 14-allergen list Israel adopted (§4.1).

### 1.9 Celery — סלרי

Celery allergy covers the stalk, root (סלרי שורש / כרפס) and seed/spice; the
allergen is reported to survive cooking and cross-reacts with birch and
mugwort pollen (https://he.wikipedia.org/wiki/אלרגיה_לסלרי **[medium]**;
https://www.allergy.org.il/סלרי/ **[medium]**). On Israeli menus: מרק ירקות,
ציר, מרק עוף (celery in the stock), סלט וולדורף, and spice blends. It is on
the 14-allergen list (§4.1). No Israeli dish-level source was found beyond the
general allergy pages.

### 1.10 Sulphites — סולפיטים (E220–E228)

Sulphites are preservatives found in wine, beer, dried fruit and some sauces;
dried apricots and raisins are particularly high, and asthmatics are the
group that reacts (https://www.ynet.co.il/article/4620823 **[medium]**;
https://allergynet.co.il/פריחה/אלרגיה-למזון/רגישות-לסולפיטים/ **[medium]**).
Israeli menu carriers: יין (wine, including cooking wine in sauces), פירות
יבשים in salads and tagines (משמש מיובש, צימוקים, חמוציות), קוסקוס with dried
fruit, חרוסת, חמוצים, מיץ ענבים. On the 14-allergen list (§4.1).

### 1.11 Soy — סויה

Menu words: סויה, פולי סויה, טופו, אדממה, רוטב סויה, טריאקי, מיסו, טמפה, חלב
סויה, "חלבון צמחי", "שניצל תירס" / "שניצל טבעוני" (soy-protein based), and
margarine/lecithin (לציטין). Soy allergy "יכולה להיות חמקמקה" because the
protein is processed into many foods
(https://www.rdm.co.il/food-allergy/ **[weak]**;
https://allergy.org.il/אלרגיה-קטניות/ **[medium]**). Osem lists soy as an
allergen in every Bamba variant (§1.2). Soy sauce also carries wheat (§1.4).

---

## 2. Hebrew menu conventions that carry allergen meaning

### 2.1 Kosher categories: בשרי / חלבי / פרווה

| Term | Religious meaning | What it **guarantees** for the app | What it **does not** guarantee | Source |
|---|---|---|---|---|
| **בשרי** (meat) | contains meat or poultry, or made in a meat kitchen | at a certified kosher venue, **no dairy ingredients are deliberately used in the dish or kitchen** — margarine, soy cream, non-dairy creamer replace butter and cream | nothing about egg, fish, sesame, nuts, gluten, soy; and a "חלבי" dessert may still be sold at a meat restaurant under separate rules (the Osher Deri case: a milk-allergic woman died after a dairy dessert at a kosher meat restaurant, https://www.ynet.co.il/health/article/SyRdRSYLu **[medium]**) | OU: kashrut and allergens are judged separately https://oukosher.org/blog/consumer-kosher/kashrus-and-allergens/ **[strong]** |
| **חלבי** (dairy) | contains dairy, or made on dairy equipment | the dish **may** contain milk; a dairy restaurant serves no meat (so no בשר-based hidden ingredients) | an individual dish at a dairy restaurant may itself be milk-free — "חלבי" is a venue/kitchen status, not a per-dish ingredient flag | same |
| **פרווה** (neutral) | neither meat nor dairy by halacha | useful as a *hint*: a pareve dish is **usually** milk-free and meat-free | **not safe for milk allergy.** Halacha tolerates dairy below 1/60 and dairy-equipment residue; the Ministry of Health explicitly warns that products marked "פרווה" or "טבעוני" may contain milk protein and are unsuitable for the milk-allergic: "הסימון 'פרווה' או 'טבעוני' אינו אינדיקציה להיעדר אלרגנים" | MoH clarification reported at https://www.maariv.co.il/news/health/article-1285408 **[medium, reporting an official notice]** ; https://www.israelhayom.co.il/health/article/19915266 **[medium]** ; Wikipedia on the 1/60 rule https://en.wikipedia.org/wiki/Pareve **[medium]** |

The Israeli allergy society (Yahel) instructs milk-allergic people to rely
"אך ורק על רשימת הרכיבים ועל אזהרות האלרגנים, ולא על סימוני כשרות חלבי או
פרווה" (https://www.allergyisrael.org.il/אלרגנים-נפוצים/ **[medium]**), and the
Israel Association of Allergy and Clinical Immunology recommends milk-allergic
patients avoid pareve products altogether because of residue
(https://www.mako.co.il/health-news/Article-2acaf49ae276c91026.htm **[medium]**).

**App rule:** use בשרי/חלבי/פרווה to *raise* a milk flag (חלבי → "may contain
milk; ask"), never to *clear* one (פרווה → still "unverified" for milk
allergy; may be shown as "likely milk-free" for lactose *intolerance* only,
with the MoH caveat).

### 2.2 Other menu labels

| Label | Meaning | May the app rely on it? | Source |
|---|---|---|---|
| **כשר / תעודת כשרות** | certified kosher | For **shellfish**: yes — a certified kosher kitchen serves no shrimp, crab, squid or molluscs. For everything else: no allergen meaning. | https://sweetscent.co.il/shrimp-kosher-halacha/ **[weak]** ; OU on allergens **[strong]** |
| **מהדרין** | stricter kosher supervision ("הידור", not a different halachic status): e.g. חלב ישראל only, stricter insect checks on greens | No additional allergen meaning. Do not treat as stricter about dairy *traces*. | https://ph.yhb.org.il/17-38-04/ **[medium]** ; https://zestyburger.co.il/kosher-mehadrin-vs-regular/ **[weak]** |
| **ללא גלוטן** | gluten-free; on packaged food the Israeli threshold is **<20 ppm**, aligned to the EU | On a packaged product: yes (regulated). On a restaurant menu: a restaurant's self-declaration — Aroma and McDonald's both say their kitchens contain gluten; 10bis menus mark sections "ללא גלוטן 🌾" by the restaurant's own hand. Show as "restaurant says gluten-free; cross-contact unknown". | https://www.ynet.co.il/economy/article/sj51hea0ex **[medium]** ; Aroma disclosure **[medium]** |
| **טבעוני** | vegan (no animal products) | Useful hint for milk, egg, fish. **Not safe for milk allergy** (same MoH warning as פרווה: new precision-fermented milk proteins, BLG, are being sold in vegan-labelled products). Says nothing about sesame, nuts, soy, gluten, legumes — vegan Israeli food is *heavier* in all five. | https://www.jdn.co.il/health/2585511/ **[medium]** ; MoH via Maariv **[medium]** |
| **צמחוני** | vegetarian — typically includes egg and dairy | Clears meat and (usually) fish only. Treat egg and milk as *possible*. | (definitional; no Israeli source found — flag) |
| **ללא סוכר** | ≤0.5 g sugars/100 g (or ml) | Not an allergen label; a lactose-free **claim must not be inferred** — a court case alleged "ללא סוכר" ice cream contained 6.6 g lactose/100 g | https://dietmaya.substack.com/p/e5f **[weak]** ; https://www.hidabroot.org/article/1226391 **[weak]** |
| **ללא תוספת סוכר** | no sugar *added*; natural sugars (fruit, lactose) remain | Same; do not infer lactose-free. | same |
| **ללא לקטוז** | lactose removed/hydrolysed | Good for lactose intolerance; **unsafe for milk allergy** (protein unchanged). | Yahel rule above **[medium]** |
| **עלול להכיל** | "may contain" — the legacy voluntary Israeli trace statement; the 2025 reform keeps it running in parallel with the new highlighted-ingredient format | On packaging only; restaurant menus rarely carry it. Treat as "cross-contact declared". | https://www.ynet.co.il/economy/article/sj51hea0ex **[medium]** |

---

## 3. Israeli epidemiology that sets product priorities

### 3.1 Sesame is the Israeli allergen

- **2002, central Israel, 9,070 infants 0–2 y:** IgE-mediated food allergy
  1.2%; the most common allergens were egg, cow's milk and sesame; 6 of 14
  anaphylaxis presentations were sesame. Dalal I et al., *Allergy*
  2002;57:362–5. https://cris.huji.ac.il/en/publications/food-allergy-is-a-matter-of-geography-after-all-sesame-as-a-major/ **[strong]**
  — note the abstract ranks sesame *third*, after egg and milk; the popular
  "second only to cow's milk" phrasing was not found in the abstract.
- **2020, northern Israel, 1,932 children (mean 22 months):** food allergy
  2.8%; **sesame 0.93%, peanut 0.2%** — the same sesame-high / peanut-low
  pattern as 2002. Garkaby J et al., *JACI: In Practice* 2020 (AAAAI
  summary "Israel's food allergy conundrum: why sensitivity to sesame but not
  peanuts?"). https://www.aaaai.org/Tools-for-the-Public/Latest-Research-Summaries/The-Journal-of-Allergy-and-Clinical-Immunology-In/2020/foodall **[strong]** ;
  https://cris.tau.ac.il/en/publications/the-sesame-peanut-conundrum-in-israel-reevaluation-of-food-allerg/ **[strong]**
- Hebrew hospital pages (Ichilov) repeat that sesame is a leading cause of
  severe reactions in Israeli children:
  https://www.tasmc.org.il/bewell/interestareas/kid/alerg-kids/ **[medium]**.

Product consequence: sesame must be a first-class allergen in the Israeli
build (it only became a US "major allergen" in 2023, §5), and tahini, hummus
and halva must be matched as sesame carriers even when the menu never writes
שומשום.

### 3.2 Peanut allergy is rare — the Bamba / LEAP story

- **Du Toit G, Lack G et al., *JACI* 2008;122:978–85:** peanut allergy in
  Jewish schoolchildren was **0.17% in Israel vs 1.85% in the UK** (5,615 vs
  5,171 children); Israeli infants eat peanut (chiefly Bamba) early and
  often. https://allergysite.co.il/wp-content/uploads/2022/12/Bamba-2008-1.pdf **[strong, PDF of the paper]** ;
  https://www.confectionerynews.com/Article/2008/11/07/Early-peanut-exposure-may-reduce-chances-of-allergy-Study/ **[medium]**
- **LEAP trial (NEJM 2015):** 640 high-risk UK infants randomised to eat
  peanut (Bamba supplied by Osem, 2 g peanut protein three times a week) or
  avoid it; early eating cut peanut allergy by roughly 70–80%.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC4416404/ **[strong]** ;
  https://medreview.odus.princeton.edu/2025/06/23/bamba-babies-how-one-snack-revolutionized-global-understanding-of-peanut-allergies **[medium]**
- Current Israeli prevalence remains ~0.2% in toddlers (Garkaby 2020, §3.1).

Product consequence: peanut is a *US-first* priority and an Israel-second one;
but Bamba itself (54% peanut, §1.2) and peanut-heavy Asian dishes still need
coverage because peanut reactions are severe when they do occur.

### 3.3 Celiac disease in Israel

- **Screening of 850 18-year-old conscripts:** diagnosed CD 0.12%, serology
  positive **1.1%**, overt-to-silent ratio 1:8 (Israeli E et al., *IMAJ*
  2010). https://www.ima.org.il/MedicineIMAJ/Article.aspx?aId=252 **[strong]**
- **Urban Bedouin (Clalit records, 2012):** diagnosed 0.51% in children,
  0.12% in adults, with under-diagnosis acknowledged.
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5051084/ **[strong]**
- **Diagnosed prevalence in teens** rose from ~0.5% (1988) to **1.1%**
  (2015) (Israeli researchers in *Archives of Disease in Childhood*).
  https://itongadol.com/?p=100454 **[weak, press summary]**
- Maccabi data 2007–2015: paediatric cases nearly tripled; projected >2% in
  20–40-year-olds within a decade.
  https://www.ynet.co.il/health/article/H1JLwoYNu **[medium]**
- Knesset research centre: Israel 0.5–1% of the population.
  https://fs.knesset.gov.il/globaldocs/MMM/fd516b58-e9f7-e411-80c8-00155d010977/2_fd516b58-e9f7-e411-80c8-00155d010977_11_10337.pdf **[strong]**

**Not verified:** a single current official figure. Use "about 1 in 100,
most undiagnosed" and cite the IMAJ conscript study.

### 3.4 Lactose intolerance in Israel and the Middle East

- **Genotype study, 439 Israelis (Raz M et al., 2013):** the lactase
  non-persistence genotype (LCT-13910 CC) was found in **97% of Bedouin
  Arabs, 93% of Iraqi Jews, 83% of Ashkenazi Jews, 82% of Moroccan Jews**;
  lactase-persistence genotypes only 4–18% by group. Genotype, not
  symptoms. https://cris.bgu.ac.il/en/publications/frequency-of-lct-13910ct-and-lct-22018ga-single-nucleotide-polymo-3/ **[strong]**
- **Global meta-analysis (Storhaug 2017, *Lancet Gastro Hepatol*):** lactose
  malabsorption 68% worldwide, **~70% in the Middle East**; no Israel-specific
  figure was visible in the abstract. https://pubmed.ncbi.nlm.nih.gov/28690131/ **[strong]**
- Clalit: no Israeli prevalence study exists; estimates "very high (about
  50% by some sources)". https://www.clalit.co.il/he/medical/medical_diagnosis/Pages/lactose_intolerance.aspx **[medium]**
- Ichilov: over 60% of Israeli adults show some decline in lactase activity.
  https://www.tasmc.org.il/health/gastro/lactase-paper/ **[medium]**

Product consequence: lactose intolerance is likely the single most common
restriction among Israeli users, far ahead of any IgE allergy — but it is a
*dose* problem, so "contains some butter" and "is a cheese plate" should be
different severities, unlike a true milk allergy.

### 3.5 Cow's-milk allergy (for completeness)

Katz Y et al., *JACI* 2010 (13,019 Israeli infants): IgE-mediated cow's-milk
allergy **0.44–0.59%**; early formula exposure was associated with far lower
incidence. https://cris.tau.ac.il/en/publications/early-exposure-to-cows-milk-protein-is-protective-against-ige-med/ **[strong]**
A follow-up found most infants avoiding milk did not actually have CMA
(243 of 381). https://www.dairyreporter.com/Article/2013/05/30/Misdiagnosed-cow-s-milk-allergy-in-infants-potentially-harmful/ **[medium]**

---

## 4. Israeli restaurant allergen regulation and platform practice

### 4.1 Packaged food: the 2025/2028 reform

- The Ministry of Health adopted EU Regulation 1169/2011's allergen scheme:
  the 14 groups (gluten cereals, crustaceans, eggs, fish, peanuts, soy, milk,
  tree nuts, celery, mustard, sesame, sulphites, lupin, molluscs), highlighted
  inside the ingredient list. **Voluntary from 1 Jan 2025, mandatory for all
  food business operators from 1 Jan 2028**; old-format stock may sell out.
  https://www.maariv.co.il/news/health/article-1245520 **[medium]** ;
  https://www.ice.co.il/consumerism/news/article/1088607 **[medium]** ;
  https://www.teamfrance-export.fr/infos-sectorielles/39650/39650-nouvelles-obligations-detiquetage-des-allergenes **[medium]**
- The Ministry's own guide: "מדריך סימון 1169/2011", version 2, 29 June 2025.
  https://www.gov.il/BlobFolder/generalpage/allergens-guidance/he/files_publications_units_food_control_services_allergens-guidance.pdf **[strong]**
- Gluten-free claim threshold **<20 ppm**; the legacy voluntary "עלול להכיל"
  statement continues in parallel.
  https://www.ynet.co.il/economy/article/sj51hea0ex **[medium]**

### 4.2 Restaurants: no duty today, and none found for 2028

- The 2022 draft regulations state the first stage applies to **pre-packaged
  food only**, including packaged raw materials delivered to catering
  businesses, and that regulating allergen information for non-pre-packaged
  food "will be examined at a later stage" ("בשלב מאוחר יותר, תיבחן האפשרות
  להסדרת מתן מידע ... גם על מזון שאינו ארוז מראש").
  https://tazkirim.gov.il/s/legislativeworkactivity/a133Y00000K4MkhQAF/הפצה-להערות-ציבור?language=en_US **[strong]** ;
  https://www.chamber.org.il/foreigntrade/1109/1110/136721/ **[medium]**
- A Ministry tender document says the intention is first to apply the rule to
  producers and importers, with a "gradual approach" for sellers of
  non-pre-packaged food.
  https://www.gov.il/BlobFolder/rfp/cfb-852/he/files_invitation-to-tender_cfb-852.pdf **[strong]**
- A Knesset legal review of other countries' rules on allergen information for
  unpackaged/restaurant food exists but does not describe an Israeli duty.
  https://fs.knesset.gov.il/globaldocs/MMM/17e5347d-18b6-e611-80ca-00155d020699/2_17e5347d-18b6-e611-80ca-00155d020699_11_7007.pdf **[strong]**
- Older legal commentary: the law "אינו מחייב בעלי מסעדות לדווח לסועדים על
  חומרים אלרגניים". https://www.bar-oncohen.co.il/essays/index.php?action=9.html **[weak, dated]**
- The EpiPen-in-every-restaurant bill (MK Yinon Azulai, after Osher Deri's
  death) was filed; reports say restaurants were later carved out of the
  version that advanced, while schools got the EpiPen duty.
  https://www.israelhayom.co.il/article/871289 **[medium]** ;
  https://www.themarker.com/news/health/2021-04-20/ty-article/.premium/0000017f-dc12-db5a-a57f-dc7aaed60000 **[medium]**
- **Re-checked 2026-10-19:** a web search excerpt of the Ministry's own
  guide (above, v2 29 Jun 2025) says the requirement for non-prepacked
  food is deferred and applies in Israel from **1.1.2032**; the excerpt
  was garbled and a direct search for the date found nothing else, so the
  date stays **unconfirmed**. Press reports of the Oct 2025 announcement
  tie 2028 to packaged food only
  (https://www.israelhayom.co.il/business/consumers/article/19118233 ;
  https://finance.walla.co.il/item/3790019 **[medium]**). A 2020 blog
  (https://mayatzur.com/2020/03/11/ **[weak, dated]**) claims a
  mass-catering timetable from July 2026 that no official source repeats;
  not adopted.
- **Not verified:** any 2028 obligation on restaurant menus. Every source
  found ties 2028 to packaged food. The app should assume restaurant
  allergen information in Israel is **voluntary** for the foreseeable future
  and that chains (Aroma, McDonald's) publish disclaimers rather than
  per-dish grids.

### 4.3 Patient associations and restaurant lists

- **Yahel (עמותת יה"ל, allergyisrael.org.il)**, founded 2007 by parents,
  lobbies on labelling law and food-industry education; no restaurant
  directory found. https://www.allergyisrael.org.il/about/ **[medium]**
- Third-party "allergy-aware" lists exist: Rest.co.il's kosher
  "allergy-awareness" filter (155 venues)
  https://www.rest.co.il/kosher-restaurants/israel/kosher/allergy-awareness/ **[weak]**
  and alergim.com's central-Israel list
  https://www.alergim.com/מסעדות-מומלצות-לאלרגים-במרכז **[weak]**.
- **Celiac:** two organisations — עמותת הצליאק (celiac.org.il, since 1998)
  and ארגון זכויות הצליאק (celiacrights.org.il). A restaurant seal issued
  after cross-contact training was announced in 2017
  (https://www.ynet.co.il/articles/0,7340,L-4968865,00.html **[medium]**);
  **not verified** whether it launched. Blogger lists (wheatout.co.il) are the
  de-facto gluten-free restaurant guides. **[weak]**

### 4.4 Wolt Israel and 10bis: what the platforms show

**Wolt** — verified from indexed wolt.com/isr pages (the agent could not open
them directly):

- Venue-level dietary tags and emoji exist: "Vegan 🌱 Gluten-free 🌾" beside a
  venue name (HaKosem), and city-wide category pages for "Gluten-free" and
  "Vegan". https://wolt.com/en/isr/tel-aviv/category/gluten-free ;
  https://wolt.com/en/isr/tel-aviv/discovery/category-vegan **[medium]**
- Dish-level information is restaurant-written text, e.g. Tandoori Herzliya:
  "Misi Masala Roti 🌱 … Gluten Free" with a note that the kitchen is not
  fully gluten-free. https://wolt.com/en/isr/tel-aviv/restaurant/tandoori-herzeliya/items/vegan-dishes-12 **[medium]**
- Wolt's terms (Germany text found; Israel's not located) say allergy
  questions go to the partner and Wolt does not verify restaurant
  information. https://explore.wolt.com/en/deu/terms **[medium]**
- **Not verified:** a structured allergen field in Wolt's Israeli assortment
  JSON. The app already parses that payload (`wolt_menu_mapper.dart`); the
  recorded fixture should be checked for any `dietary`/`allergen`-like keys
  before assuming none.

**10bis** — verified from indexed 10bis.co.il menu pages:

- Restaurant-level category tags such as "סושי, אסייתי, ללא גלוטן".
- Dish-level labels are **free text** in headings or item names: section
  "סושי ללא גלוטן 🌾", item "תבשיל קטניות- טבעוני/ללא גלוטן", footnote "ניתן
  לקבל טבעוני". https://www.10bis.co.il/next/Restaurants/Menu/Delivery/3620/זה%20סושי ;
  https://www.10bis.co.il/next/Restaurants/Menu/Delivery/24585/פילאף%20פוד%20בר%20אוכל%20מוכן **[medium]**
- **Not verified:** any standardised allergen field; no help-centre page found.

Parser implication: treat 🌱/🌾, "טבעוני", "ללא גלוטן", "צמחוני" wherever
they appear (venue tag, heading, item name, option text, footnote) as
restaurant self-declarations with the §2.2 caveats, and never as allergen
clearance.

---

## 5. US supplement: cuisine-specific hidden allergens

The US context differs in two ways: sesame became the ninth federal "major
allergen" only on 1 Jan 2023
(https://community.kidswithfoodallergies.org/blog/young-advocates-propel-bill-forward-to-label-food-allergens-on-restaurant-menus **[medium]**),
and restaurant food is outside federal labelling law — KFA notes no federal or
state menu-allergen rule as of 2025, with California's ADDE Act (chains with
20+ locations, top-9 allergens in writing, no cross-contact labelling) the
first to move
(https://community.kidswithfoodallergies.org/blog/new-california-bill-would-require-allergen-labeling-on-restaurant-menus **[medium]**).
**Checked 2026-10-19: signed.** This is SB 68: signed by the Governor on
13 Oct 2025, in force from 1 July 2026 (§8.1 has the sources). File 06's
"SB 68" and this section's "ADDE Act" are the same law. FARE's registry found reactions cluster at
cafes, fast food, **Asian restaurants**, ice-cream parlours and bars
(https://www.foodallergy.org/fare-blog/fare-patient-registry-data-sheds-light-prevention-and-management-food-allergy-reactions **[strong]**).

| Cuisine | Hidden allergen | Carrier | Source |
|---|---|---|---|
| **Asian** (Chinese, Thai, Vietnamese, Japanese, Indian, Indonesian) | peanut | sauces, lo mein, egg rolls (peanut butter in egg rolls reported), satay; FARE rates these cuisines high cross-contact risk even for peanut-free orders | https://www.foodallergy.org/living-food-allergy/food-allergy-essentials/common-allergens/peanut **[strong]** ; https://www.spokin.com/hidden-allergens **[medium]** |
| | peanut oil | cold-pressed/expelled oil retains protein; refined is usually tolerated — ask | FARE peanut page **[strong]** |
| | fish / shellfish | fish sauce as a base flavour; oyster sauce in stir-fry sauces, soups, marinades; shrimp paste; prawn crackers | FARE dining-out guide https://www.foodallergy.org/resources/dining-out **[strong]** ; ASCIA shellfish guide **[strong]** ; https://www.partstown.com/about-us/seafood-allergies-in-restaurants **[weak]** |
| | sesame | sesame oil in spicy tuna, sesame chicken, pad thai, sushi | https://www.spokin.com/ordering-by-allergen **[medium]** |
| | soy, wheat | soy sauce (wheat), hoisin (soy, gluten, sesame), teriyaki; most Japanese/Korean sauces | https://celiac.org/dining-and-social-eating/ **[strong]** ; https://celiac.org/2023/06/28/traveling-gluten-free/ **[strong]** |
| | egg | egg noodles, fried rice, tempura batter | https://www.spokin.com/egg-allergy-friendly-asian-restaurant-guide **[medium]** |
| **Mexican** | wheat | flour tortillas (burritos, quesadillas, "soft tacos"); corn tortillas cooked on a comal shared with flour | https://support.gringostexmex.com/hc/en-us/articles/360034344433 **[weak, chain help page]** ; comal note from a taqueria allergen page via search **[weak]** |
| | lard (pork) and chicken stock | refried beans, flour tortillas, rice | Gringo's page above **[weak]** |
| | peanut, tree nuts, sesame | mole poblano, mole pipián, enchilada sauce (FARE lists enchilada and mole sauce as peanut hiders) | FARE peanut page **[strong]** ; Spokin hidden-allergens entries (Ola Mexican Kitchen, La Mission) **[medium]** |
| | milk | crema, queso fundido, elote, "cheesy" dishes | menu pages via search **[weak]** |
| **Italian** | tree nuts | pesto (pine nuts; trapanese pesto has almonds), pistachio in mortadella, hazelnut in desserts, cannoli | https://www.wyndly.com/blogs/learn/pesto-allergy **[weak]** ; https://italyplanner.com/italy-allergies-guide-dining.html **[weak]** ; Spokin cannoli entry **[medium]** |
| | milk | pesto (Parmesan), risotto (butter, cheese), breadcrumbs that contain milk | HelloFresh label "Italian Breadcrumbs (Contains: Wheat, Milk, Oats, Rye, Sesame, Soy, Barley)" https://www.hellofresh.ca/recipes/classic-turkey-meatballs-6829eb1d99bb603b9b4386e6 **[weak, but a real label]** |
| | egg, wheat | meatball binders (breadcrumbs + egg), fresh pasta, Caesar dressing (egg, anchovy, mustard, milk) | same HelloFresh labels **[weak]** |
| | fish | anchovy in Caesar and puttanesca | same |
| **American / fast food** | milk | buttermilk-brined and -breaded fried chicken (McDonald's buttermilk crispy chicken, cooked in the same fryer as other chicken) | https://community.kidswithfoodallergies.org/blog/milk-allergy-alert-mcdonald-s-fried-chicken-items **[medium, 2015]** |
| | wheat, milk, shellfish via oil | **shared fryers**: fries cooked with breaded chicken or shrimp; heat does not destroy allergens | https://www.foodservicedirector.com/operations/4-hidden-sources-allergens **[medium]** ; CDF dining checklist (dedicated fryer, oil change) https://celiac.org/dining-and-social-eating/ **[strong]** |
| | wheat | omelettes with pancake batter, flour-dusted baked potatoes | BIDMC celiac centre https://bidmc.org/-/media/files/bidmc/digestive-care/celiac-center/educational-materials/nutrition/bidmc-dining-out-travel-tips-celiac-disease.pdf **[strong]** |
| | peanut oil | some chains fry in peanut oil (Spokin lists a Jimmy John's chips case) | https://www.spokin.com/hidden-allergens **[medium]** |
| | various | desserts bought in from outside bakeries — staff lack ingredient lists | FARE dining-out guide **[strong]** |
| | regional variation | chain recipes differ by region, so a safe item in one state may not be in another | https://community.kidswithfoodallergies.org/blog/reminder-restaurant-foods-may-have-different-ingredients-by-region **[medium]** |

Shared-fryer evidence is mixed: a 2026 symposium abstract testing 98 fries and
chip samples from US restaurants found only 6.1% above 20 ppm gluten, higher
with weekly than daily oil changes
(https://icds.p.asnevents.com.au/days/2026-11-20/abstract/139049 **[medium,
abstract]**); CDF still advises asking for a dedicated fryer.

**Checked 2026-10-19 (the trip lexicon's US entries).** Enchilada sauce,
mole, chili and egg rolls as peanut hiders: confirmed by hospital and
state peanut-diet sheets ("may be thickened with peanut butter")
(https://www.cedars-sinai.org/health-topics/peanut-allergy-diet **[M]** ;
https://www.decal.ga.gov/documents/attachments/Child-Care-Center-Food-Allergy-Fact-Sheet-Peanuts.pdf **[S]**).
Sesame oil in spicy tuna: confirmed, weakly — most published recipes mix
mayonnaise, sriracha and sesame oil
(https://www.justonecookbook.com/wprm_print/spicy-tuna **[W]** ;
https://www.kitchenaid.com/countertop-appliances/recipes/spicy-tuna-roll **[W]**).
Sesame in pad thai: **unconfirmed** — the recipes and meal-kit labels found
use peanuts, fish sauce and egg but no sesame oil
(https://www.gastronomixs.com/en/components/pad-thai **[W]**); only Spokin
reports it, so the lexicon keeps it as "sesame oil is reported", a
suspected trigger that asks and never avoids. The other rows of this
table remain **unreviewed** beyond their original sources.

---

## 6. Implications for the app (summary)

1. Israel-first allergen order: **sesame, milk/lactose, gluten, egg, legumes
   (incl. soy), tree nuts, peanut, fish/shellfish**, then the EU-14 remainder
   (mustard, celery, sulphites, lupin, molluscs). US-first order: peanut, tree
   nuts, milk, egg, wheat, soy, fish, shellfish, sesame.
2. The parser must infer sesame from טחינה/חומוס/חלבה/בורקס/פלאפל, egg from
   מיונז/סביח/שניצל, wheat from קוסקוס/פתיתים/בורגול/ג'חנון/מלאווח/רוטב סויה,
   and legumes from פלאפל/מג'דרה/חילבה — none of these dishes names its
   allergen on a menu.
3. Kosher words are one-directional: חלבי raises a milk flag; כשר clears
   shellfish; פרווה, טבעוני and ללא לקטוז **never** clear milk allergy.
4. Platform tags (Wolt 🌱🌾, 10bis "ללא גלוטן") are restaurant
   self-declarations; show them, never trust them.
5. Expect no regulatory help from Israeli restaurant menus before 2028, and
   possibly after; packaged-ingredient disclosure (2028) will improve what
   chains *could* publish, not what they must.

---

## 7. Hebrew menu terms for the extended restrictions (ALG-17)

**Status: desk research, added on 2026-10-15 for ALG-17, not clinical
review. Checked 2026-10-19, in part:** the English food facts behind the
tables are file 11 §17 and §21–§23, whose sources were re-checked that day
(file 11 §21–§23 status lines); alpha-gal's gelatin, mammal fats and stock
are confirmed by CDC and state health material
(https://stacks.cdc.gov/view/cdc/131346/cdc_131346_DS1.pdf **[strong]** ;
https://www.mass.gov/doc/alpha-gal-syndrome-information-for-local-boards-of-health-and-food-establishments/download **[strong]**),
and shawarma's meat as chicken, turkey or lamb (so "suspected" for
alpha-gal, as the table has it) by restaurant directory text
(https://www.b144.co.il/%D7%A9%D7%95%D7%95%D7%90%D7%A8%D7%9E%D7%94/%D7%91%D7%AA-%D7%99%D7%9D/ **[weak]**).
**Still unreviewed:** the Hebrew spellings themselves, which no web source
can confirm; they need a native-speaking dietitian. These are the Hebrew
spellings an Israeli menu uses for the
foods that file 11 §17 (alpha-gal) and §21–§23 (FODMAP, histamine, GLP-1
eating) list in English, with the sources cited there. As §20 of file 11
says of all Hebrew dish vocabulary, they are the app's own lexicon, not
sourced medical content: no Hebrew clinical page was consulted, and a
native-speaking dietitian should review them. Spelling variants follow §1
(geresh and apostrophe read alike; the parser allows the grammatical
prefixes ב/ה/ו/כ/ל/מ/ש unless a term is listed as taking none).

### 7.1 Alpha-gal — אלפא-גל (mammalian meat)

| Term | Meaning | Use |
|---|---|---|
| בקר, עגל, כבש, טלה, חזיר, עז, צבי, ארנב | beef, veal, mutton, lamb, pork, goat, venison, rabbit | direct |
| אנטריקוט, סינטה, שייטל, פיקניה, אסאדו, ספריבס, אוסובוקו | beef and veal cuts | direct |
| ג'לטין, שומן חזיר, שומן כבש | gelatin and mammal fat (via חזיר/כבש); tallow is not listed, because its Hebrew חֵלֶב is spelled as milk | direct |
| לשון, מח עצם, ציר בקר, מרק עצמות | tongue, bone marrow, beef stock, bone broth | direct (ציר בקר via בקר) / likely |
| בשר | "meat": on an Israeli menu usually beef or lamb, while poultry is עוף | likely; lowered beside עוף/הודו/דג |
| המבורגר, קבב, עראייס, קציצות, סטייק, קרפצ'יו, פסטרמה, סלמי, נקניקיה, קבנוס, מרגז, בייקון, צ'ולנט, חמין | beef or lamb dishes and cured meats (turkey versions exist: פסטרמה הודו, נקניקיית עוף) | likely; lowered beside עוף/הודו/דג/טונה/סלמון/סלק/כרובית |
| כבד, כבדים | liver — beef or chicken (כבד עוף) | likely; lowered beside עוף/אווז/ברווז |
| שווארמה, נקניק, קובה, ציר, שומן | often turkey or chicken in Israel; mixed or unknown fat and stock | suspected |
| פנקוטה, מרשמלו, ג'לי, סוכריות גומי | gelatin desserts | likely (ג'לי suspected) |

Dairy, which some people with alpha-gal syndrome react to (file 11
§17.2), is not listed: the Milk restriction carries it, and a person who
reacts to dairy adds that entry too.

### 7.2 FODMAP — פודמאפ

| Term | Meaning | Use |
|---|---|---|
| בצל, בצלים, שאלוט, כרישה, שום (and בשום, ושום, השום, ובשום) | onion, shallot, leek, garlic | direct; שום takes no free prefix, since משום is "because" |
| חומוס (the chickpea), גרגרי חומוס, עדשים, שעועית, פול | chickpeas, lentils, beans, fava | direct (חומוס the dish: hidden, likely) |
| תפוח, תפוחים, אגס, אגסים, מנגו, אבטיח, דבש, סילאן, אגבה | apple, pear, mango, watermelon, honey, date syrup, agave | direct; תפוח lowered before אדמה (potato) |
| חלב, יוגורט, גלידה, ריקוטה, גבינת קוטג' | lactose foods | direct; חלב lowered before שקדים/סויה/שיבולת שועל/קוקוס/אורז |
| כרובית, פטריות, פטרייה, ארטישוק, אספרגוס, קשיו, פיסטוק, משמש, אפרסק, שזיף, דובדבנים | polyol and fructan foods | direct |
| פלאפל, מג'דרה, ציר, מרק, רוטב שום, איולי, צזיקי, פסטו, סלסה | hidden onion, garlic, chickpea, lentil | likely / suspected |
| לחם, פיתה, פסטה, קוסקוס | wheat in a full serving | suspected |

### 7.3 Histamine — היסטמין

| Term | Meaning | Use |
|---|---|---|
| פרמזן, פרמג'יאנו, צ'דר, גאודה, אמנטל, רוקפור, גורגונזולה, קממבר, ברי, גבינה מיושנת | aged cheeses | direct |
| סלמי, פפרוני, פרושוטו, בייקון, פסטרמה, קבנוס, נקניק, צ'וריסו | cured and processed meats | direct |
| טונה, מקרל, סרדינים, אנשובי, הרינג, דג מעושן, סלמון מעושן | histamine-prone fish | direct |
| כרוב כבוש, קימצ'י, חמוצים, מלפפון חמוץ, מיסו, טמפה, קומבוצ'ה, קפיר | fermented foods | direct |
| חומץ, בלסמי, יין, בירה, שמפניה | vinegar and alcohol | direct |
| רוטב סויה, רוטב דגים, קטשופ, רוטב ווסטרשייר | fermented and vinegar sauces | likely |
| עגבניה, עגבניות, רסק עגבניות, תרד, חציל, חצילים, אבוקדו, תות, תותים, אננס, שוקולד | histamine-rich or "liberator" foods | suspected |

### 7.4 Small portions (GLP-1) — מנות קטנות

| Term | Meaning | Use |
|---|---|---|
| מטוגן, מטוגנת, מטוגנים, מטוגנות, טמפורה, שניצל, צ'יפס | fried | likely |
| שמנת, רוטב שמנת, קרמי, אלפרדו, קרבונרה | creamy | likely |
| כפול, כפולה, משולש, ענק, ענקית, מגש, משפחתי, ללא הגבלה | large portions | likely |
| גדול, גדולה | "large" | suspected |
| קולה, מוגז, לימונדה, מילקשייק, שייק, ברד, סירופ, קינוח, קינוחים, עוגה, עוגת, גלידה, בראוניז | sugary drinks and desserts | likely |

---

## 8. Trip mode: restaurant duties and local hidden-ingredient lexicons (ALG-13)

**Status: checked 2026-10-19, in part.** Added on 2026-10-15 for ALG-13
(issue #355) from general culinary and regulatory knowledge. On
2026-10-19 §8.1 (every row) and the lexicon entries a wrong claim would
hurt most were checked against **web search results**; this environment
still cannot open a page (every direct fetch failed at DNS or was refused
by the egress proxy), so every check rests on result excerpts, and the
URL and grade sit beside each claim. Rows marked **checked** cite their
source; rows without a mark remain **unreviewed desk research** and need a
reviewer with a browser (a national allergy charity, the regulator, a
standard recipe reference) before their wording is final. No claim was
upgraded: corrections only removed or softened wording. Where a fact is
already sourced elsewhere in file 11 or this file, the code cites that
section instead of this one. The lists are
deliberately short: a trip-mode term is only ever a *suspected* trigger,
which turns a strict entry's dish into "ask", never into "avoid", and
never clears anything. Terms are the Latin-script words a menu at the
destination prints (romanised for Japan: the matcher cannot read kana or
kanji); `TripLexicon` in `lib/utils/allergens/trip_lexicon.dart` holds
them with their glosses.

### 8.1 Who must tell you: packaged food versus restaurants

| Jurisdiction | What its list binds | Hint the app shows for a listed allergen | Basis (checked 2026-10-19) |
|---|---|---|---|
| EU (France, Italy, Spain, Germany) | packaged **and** non-prepacked food: under Article 44 of Regulation 1169/2011 the Annex II allergen particulars are mandatory for food sold non-prepacked, so a restaurant must be able to say which of the 14 a dish holds; each member state may set the *means* (in writing or orally) | "the restaurant must be able to tell you — still ask" | **confirmed**: https://www.legislation.gov.uk/eur/2011/1169/article/44 **[S]** ; Commission notice on Annex II (2017) https://elelmiszerlanc.kormany.hu/akadalymentes/download/2/1f/d1000/labelling_legislation_guidance_allegens-2017-4864_en%20published.pdf **[S]** |
| United Kingdom | the same 14 for non-prepacked food (Food Information Regulations 2014): the information may be given orally if a sign says so. The FSA's March 2025 best-practice guidance asks for written information plus a conversation, but is not law; "Owen's Law", the campaign to make writing mandatory, has not been enacted. Natasha's Law (1 Oct 2021) covers only food prepacked for direct sale (full ingredient list, allergens emphasised) | the same | **confirmed**: https://www.food.gov.uk/news-alerts/news/updated-industry-guidance-issued-for-food-allergen-information-in-the-out-of-home-sector **[S]** ; https://food.gov.uk/business-guidance/allergen-information-for-non-prepacked-foods-best-practice-approach **[S]** ; https://www.allergyuk.org/news/17778/ **[M]** ; https://www.open.edu/openlearn/health-sports-psychology/owens-law-the-case-written-allergen-information-every-food-business **[M]** ; https://www.food.gov.uk/news-alerts/news/millions-with-food-allergies-to-benefit-as-new-allergen-labelling-law-comes-into-force **[S]** |
| Israel | packaged food only, voluntary from 1 Jan 2025 and mandatory from 1 Jan 2028; restaurants have no duty today. Non-prepacked food is deferred — to 1 Jan 2032 per one garbled search excerpt of the Ministry guide (**unconfirmed**) | "labelled on packaged food only — ask every time" | **confirmed** (the 2028 rule and its scope): §4.1–§4.2; https://www.teamfrance-export.fr/infos-sectorielles/39650/39650-nouvelles-obligations-detiquetage-des-allergenes **[M]** ; https://www.israelhayom.co.il/business/consumers/article/19118233 **[M]** ; https://www.gov.il/BlobFolder/generalpage/allergens-guidance/he/files_publications_units_food_control_services_allergens-guidance.pdf **[S, excerpt only]** |
| United States | packaged food (FALCPA, FASTER Act); restaurant food is outside federal law. **California SB 68**, the Allergen Disclosure for Dining Experiences ("ADDE") Act, was **signed on 13 Oct 2025** and took effect on **1 July 2026**: a food facility in a chain of **20 or more locations** (same name, substantially the same menu items) must give **written notification** of the nine major allergens each menu item contains as an ingredient, on the menu or in a digital format (with an alternative for people without the technology). It requires **no cross-contact** statement. File 06's "misdemeanour for not disclosing cross-contact" was wrong on cross-contact (corrected there); the penalty itself was not confirmed | "labelled on packaged food; only large chains in California must list it — ask every time" | **confirmed**: https://sd20.senate.ca.gov/news/california-first-nation-require-allergen-disclosures-restaurant-menus-sb-68 **[S, the author's office]** ; https://community.kidswithfoodallergies.org/blog/governor-newsom-signs-aafa-bill-to-require-allergen-labeling-in-california-restaurants **[M]** ; https://www.allergicliving.com/2026/06/29/adde-allergens-on-menu-act-takes-effect-inspiring-more-states/ **[M]** ; https://www.fisherphillips.com/en/insights/insights/many-restaurant-chains-must-comply-with-californias-new-allergen-disclosure-law **[M, law firm]** ; https://www.gtlaw.com/he/insights/2025/9/california-poised-to-become-first-state-to-mandate-food-allergen-disclosures-for-restaurants-sb-68-awaits-gov-newsoms-signature **[M, law firm]**. The bill text on leginfo.legislature.ca.gov was refused by the egress proxy |
| Japan | packaged processed food only: restaurants, take-away counters and food sold face to face are outside the labelling rules, and any menu allergen information is voluntary. Since **1 April 2026** the mandatory list is **nine** (egg, milk, wheat, shrimp, crab, peanut, buckwheat, walnut, and cashew, with a transition to 31 March 2028) and the recommended list twenty (pistachio added) | "labelled on packaged food only — ask every time" | **confirmed**: https://www.foodallergy.jp/2022-nutrition-dietary-guidelines/ndg2022-7/ **[S, the Japanese Society for Food Allergy's guideline]** ; https://www.pref.yamanashi.jp/shokuhin-st/shokuhinhyouji/kurumi.html **[S, prefecture]** ; https://www.pref.fukushima.lg.jp/sec/21045e/syokuhinhyouji-allergen.html **[S, prefecture]** ; https://food.chemlinked.com/news/food-news/new-compliance-alert-mandatory-labeling-changes-for-food-exports-to-japan **[M]** ; https://tabemasen.io/allergies/labeling-guide/ **[W]**. The Consumer Affairs Agency's own page was not reached |
| Canada, Australia / New Zealand | not researched as restaurant rules (not trip destinations yet) | read as packaged-only, the side that never overstates a duty | their packaged lists: file 11 §19.4 (PEAL's "gluten" required name re-checked 2026-10-19: https://foodlabelmaker.com/regulatory-hub/fsanz/peal-allergen-labelling-guide/ **[W]** ; https://agriexchange.apeda.gov.in/ImportRegulations/New%20Allergen%20Labeling%20Requirement%20for%20Australia%20and%20New%20ZealandCanberraAustraliaAS20240007.pdf **[M]**) |

Japan's mandatory list includes **buckwheat**, which has no restriction id
in the taxonomy (file 02); the briefing tells a buckwheat-allergic user to
add it as their own word (ALG-17), and lists soba under wheat and gluten
because most soba is cut with wheat flour.

### 8.2 Japan

| Term | Hides | Why (to confirm) |
|---|---|---|
| soba | wheat, gluten (and buckwheat) | buckwheat noodles commonly mixed with wheat flour (*ni-hachi*: about 20% wheat) |
| yakisoba | wheat, gluten, soy | wheat noodles fried in a Worcestershire-style soy sauce |
| udon, ramen | wheat, gluten | wheat noodles |
| miso | soy, gluten | soy paste; *mugi* (barley) miso holds gluten |
| tempura | wheat, gluten, eggs | wheat-flour batter, often with egg |
| ponzu | soy, wheat, gluten, fish | citrus soy sauce, usually seasoned with dashi |
| katsu, tonkatsu | wheat, gluten, eggs | flour, egg and panko coating; the sauce holds wheat and soy |
| okonomiyaki | wheat, gluten, eggs, fish | wheat-and-egg batter, topped with bonito flakes |
| takoyaki | wheat, gluten, eggs, molluscs, fish | octopus in wheat batter, topped with bonito |
| furikake | sesame, fish | rice seasoning of sesame, nori and dried fish |
| goma, gomadare | sesame | *goma* is sesame; *gomadare* sesame sauce, *goma-ae* sesame-dressed greens |
| mentaiko | fish | spicy pollock roe |
| tamagoyaki, tamago | eggs, fish | rolled omelette, often seasoned with dashi |
| gyoza | wheat, gluten | wheat wrappers |

**Checked 2026-10-19 (Japan).** *soba*: confirmed — only *juwari*
soba is buckwheat alone; *ni-hachi* is about 80% buckwheat and 20% wheat,
and supermarket soba may be mostly wheat
(https://www.healthline.com/nutrition/soba-noodles **[M]** ;
https://www.americastestkitchen.com/taste_tests/2030-soba-noodles **[M]**).
*shoyu*: confirmed — standard (*koikuchi*) soy sauce is brewed from soy
and wheat in roughly equal parts; tamari has little or no wheat, so the
gloss now says "standard soy sauce", and "in most sauces" became "many
Japanese sauces"
(https://www.kikkoman.co.uk/inspiration/difference-between-tamari-and-regular-soy-sauce/ **[M, manufacturer]** ;
https://japanesetaste.com/blogs/japanese-taste-blog/tamari-vs-soy-sauce-whats-the-difference-and-which-should-you-use **[W]**).
*dashi*: **corrected** — usually bonito flakes (*katsuobushi*) or dried
sardines (*niboshi*), but kelp-only dashi exists, so the gloss no longer
says it is "made from bonito"; fish stays its hidden restriction
(https://www.japanryokanguide.com/en/blog/food-allergy-ryokans-japan **[W]** ;
undeclared bonito and sardine in a packaged dashi, FDA recall
https://www.fda.gov/safety/recalls-market-withdrawals-safety-alerts/jfc-international-inc-issues-allergy-alert-undeclared-fish-bonito-sardine-tuna-wel-pac-shrimp-soup **[S]**).
Buckwheat's place on the mandatory list: confirmed (§8.1). The other rows
of this table remain **unreviewed**.

Shoyu, teriyaki (file 11 §7.2), dashi and katsuobushi (file 11 §8.1) are
cited to file 11.

### 8.3 France

| Term | Hides | Why (to confirm) |
|---|---|---|
| viennoiserie, pain au chocolat | wheat, gluten, lupin, milk, eggs | butter pastry with egg glaze; lupin flour is used in some French doughs (file 11 §14.2 documents lupin in pastry generally) |
| moutarde, Dijon | mustard | the French word; Dijon mustard is in most vinaigrettes and many sauces |
| béarnaise | eggs, milk | egg-yolk and butter emulsion |
| beurre blanc | milk, sulphites | butter sauce reduced with white wine |
| rémoulade | mustard, eggs | mayonnaise with mustard (céleri rémoulade) |
| rouille | eggs, wheat, gluten, fish | garlic-saffron sauce thickened with yolk or bread, served with fish soup |
| financier | tree nuts, milk, eggs, wheat, gluten | almond-flour cake with brown butter |
| croque monsieur, croque madame | wheat, gluten, milk, eggs | ham-and-cheese toast with béchamel; the madame adds an egg |
| gratin, dauphinois | milk | baked in cream, milk or cheese |

**Checked 2026-10-19 (France).** *viennoiserie* and lupin: confirmed —
the French food-safety agency's 2007 opinion says lupin flour is commonly
used in bakery and *viennoiserie* products, with reactive doses as low as
265 mg and lupin 3.7% of food allergies in France
(https://www.anses.fr/fr/system/files/NUT2007sa0029.pdf **[S]** ;
Anaphylaxis UK lupin factsheet
https://www.anaphylaxis.org.uk/wp-content/uploads/2026/08/Lupin-V5.pdf **[M]**).
The gloss keeps "in some doughs": the opinion is from 2007 and no current
share was found. The other rows of the France table remain **unreviewed**.

### 8.4 Italy

| Term | Hides | Why (to confirm) |
|---|---|---|
| bagna cauda | fish, milk | warm anchovy-garlic dip, often with butter |
| tonnato | fish, eggs | tuna-mayonnaise sauce (vitello tonnato) |
| amaretti, amaretto | tree nuts | almond or apricot-kernel biscuits and liqueur |
| torrone | tree nuts, eggs | nougat with almonds or hazelnuts and egg white |
| tiramisù | eggs, milk, wheat, gluten | raw-egg mascarpone cream on savoiardi |
| fritto misto, frittura | wheat, gluten, fish, crustaceans, molluscs | floured fried seafood, usually from one fryer |
| salsa verde | fish | herb sauce, often with anchovy |
| alla milanese, impanato | wheat, gluten, eggs | egg-and-breadcrumb coating |

Pesto, trapanese, mortadella, cannoli, puttanesca and polpette are cited
to §5; gianduja to file 11 §2.1; carbonara to file 11 §5.2; bottarga to
file 11 §8.1.

**Italy:** not checked on 2026-10-19 beyond the entries shared with §5
and file 11; every row of this table remains **unreviewed**.

### 8.5 Spain

| Term | Hides | Why (to confirm) |
|---|---|---|
| mostaza | mustard | the Spanish word |
| romesco | tree nuts, wheat, gluten | pepper sauce thickened with almonds or hazelnuts and bread |
| alioli, allioli | eggs | traditionally garlic and oil, but restaurant versions are usually egg-based |
| salmorejo | wheat, gluten, eggs | tomato-bread soup topped with egg |
| gazpacho | wheat, gluten | often thickened with bread |
| croquetas | wheat, gluten, milk, eggs | béchamel, egg and breadcrumbs |
| paella | crustaceans, molluscs, fish | rice cooked in stock, often seafood stock |
| fideuà, fideos | wheat, gluten, crustaceans, molluscs | short wheat noodles cooked like paella |
| ajoblanco | tree nuts, wheat, gluten | cold almond and bread soup |
| turrón | tree nuts, eggs | almond nougat with egg white |
| rebozado, empanado, empanada | wheat, gluten, eggs | battered, breaded, or a wheat-pastry turnover |
| ensaladilla | eggs, fish | potato salad in mayonnaise, often with tuna |

**Spain:** not checked on 2026-10-19 beyond the shared entries; every
row remains **unreviewed**.

Altramuces (lupin) is cited to file 11 §14.1.

### 8.6 Germany

| Term | Hides | Why (to confirm) |
|---|---|---|
| Senf | mustard | the German word; served with every sausage and in many sauces and dressings |
| Remoulade | mustard, eggs | mayonnaise sauce with mustard |
| Rouladen, Roulade, Rinderroulade | mustard | beef rolls spread with mustard |
| Bratwurst, Wurst | mustard, wheat, gluten | sausages, some with wheat filler (file 11 §7.2 lists sausages), served with mustard |
| Spätzle, Käsespätzle | eggs, wheat, gluten (milk) | egg noodles; *Käse-* baked with cheese |
| Knödel, Semmelknödel | wheat, gluten, eggs, milk | bread dumplings bound with egg and milk |
| Maultaschen | wheat, gluten, eggs | filled pasta |
| paniert | wheat, gluten, eggs | breaded |
| Sellerie, Knollensellerie | celery | the German words for celery and celeriac |
| Suppengrün, Suppengemüse | celery | soup-vegetable bundle that includes celeriac |
| Bienenstich | tree nuts, milk, eggs, wheat, gluten | yeast cake with almond topping and custard |

**Checked 2026-10-19 (Germany).** *Rouladen*: confirmed — classic
recipes spread the beef with mustard before rolling
(https://www.lecker.de/klassische-rinderrouladen-23918.html **[W, recipe]** ;
https://www.heidelberg24.de/ratgeber/rinderrouladen-wie-bei-oma-so-gelingen-sie-garantiert-zr-94164621.html **[W]**).
*Remoulade*: confirmed, weakly — a mayonnaise (egg) sauce with mustard,
gherkins, capers and herbs (https://kvalifood.com/posts/remoulade/ **[W]**).
*Senf*: the gloss's "on every sausage" was an overstatement and now reads
"served with sausages". The other rows remain **unreviewed**.

Currywurst and Kartoffelsalat are cited to file 11 §13.2 (curry powder,
potato salad); Brühe to file 11 §12.2; Marzipan to file 11 §2.2;
Lupinenmehl to file 11 §14.1.

### 8.7 United Kingdom

| Term | Hides | Why (to confirm) |
|---|---|---|
| Yorkshire pudding | wheat, gluten, eggs, milk | batter of flour, egg and milk |
| Scotch egg | eggs, wheat, gluten | egg in sausage meat and breadcrumbs |
| coronation chicken | eggs, mustard | curried mayonnaise; curry powder may hold mustard (file 11 §13.2) |
| Bakewell | tree nuts, wheat, gluten, eggs | almond frangipane tart |
| haggis | gluten (oats), mammal meat | sheep offal with oatmeal |
| Welsh rarebit | milk, wheat, gluten, mustard, fish | cheese sauce on toast, usually with mustard and Worcestershire sauce |
| stuffing | wheat, gluten, celery | breadcrumb stuffing, often with celery or stock |
| ploughman's | milk, wheat, gluten, mustard | cheese, bread and pickle |

**United Kingdom:** not checked on 2026-10-19 beyond §8.1; every row
remains **unreviewed**.

Gravy and Marmite are cited to file 11 §12.2, brown sauce to file 11 §7.2
(malt vinegar), Worcestershire to file 11 §8.2 and piccalilli to file 11
§13.1.

---

## 9. Hebrew menu terms for kosher and halal (issue #342)

**Status: desk research, added and checked 2026-10-21, not reviewed by a
rabbi, a scholar or a native-speaking dietitian.** The food rules are
file 11 §24 (kosher) and §25 (halal), with their sources. One Hebrew usage
was confirmed on the web: **"בשר לבן" ("white meat") and "סטייק לבן" are
the accepted Israeli euphemism for pork** — Wikipedia, *White meat*
(https://en.wikipedia.org/wiki/White_meat **[M]**), the Forward, "a pork
chop is called *stek lavan*" (https://forward.com/articles/105658 **[M]**),
the JC, "shops still euphemistically call pork 'white meat'"
(https://www.thejc.com/life/food/how-the-holy-land-got-a-pork-habit-uzc8a7su **[M]**)
and New Voices (https://newvoices.org/2010/10/03/israeli-bacon/ **[W]**),
all read as search snippets. Because "white meat" also means poultry
breast, both are **likely**, never stated, and lowered beside עוף/הודו.
**Still unreviewed:** every other Hebrew spelling below, which no web
source confirms; as §7 says of all Hebrew dish vocabulary, it is the app's
own lexicon. Components only, never certification: no term here says a
dish is kosher or halal, and "כשר"/"חלאל" beside a word is a guard (a
substitute), never a declaration — only a platform's tag declares (§4.4).

### 9.1 Pork — חזיר

| Term | Meaning | Use |
|---|---|---|
| חזיר (and החזיר, וחזיר, בחזיר) | pork | direct; no free prefix, since מחזיר is "returns" |
| בשר לבן, סטייק לבן | Israeli euphemisms for pork | likely; lowered beside עוף/הודו |
| בייקון, פרושוטו, פנצ'טה | bacon, prosciutto, pancetta | likely; lowered beside בקר/הודו/עוף/אווז/ברווז/טלה (beef and goose bacon are common on kosher menus) |
| סלמי, פפרוני, צ'וריסו, נקניק | cured meats, usually beef or turkey in Israel | suspected; lowered beside עוף/הודו/בקר |

### 9.2 Shellfish and other animals (kosher)

| Term | Meaning | Use |
|---|---|---|
| שרימפס, סרטן, לובסטר, קלמרי, מולים, פירות ים … | shellfish | §1.7's crustacean and mollusc terms, reused |
| צלופח, אונאגי, שפמנון, פנגסיוס, כריש | eel, catfish, pangasius, shark | direct; "רוטב אונאגי" (eel sauce) lowered |
| חדקן, קוויאר, קביאר | sturgeon, caviar | likely; קוויאר lowered beside חצילים/סלמון/פורל/עדשים |
| דג חרב | swordfish | suspected (disputed, file 11 §24.2) |
| ארנב, ארנבת | rabbit, hare | direct |

### 9.3 Meat with dairy (kosher)

The meat side of file 11 §24.5's rule: §7.1's mammal meats and cuts, plus
בשר (no free prefix; and הבשר, בבשר, ובשר), עוף, עופות, הודו, ברווז, אווז,
פרגית, שניצל, המבורגר, קבב, קציצות, סטייק, שווארמה, שיפודים, פסטרמה,
סלמי, נקניקיה, קבנוס, מרגז, עראייס, כבד, צלעות, צ'ולנט, חמין, and ציר
(suspected). Lowered beside a fish or a vegetable (שניצל תירס, קציצות דגים,
סטייק כרובית, ציר ירקות). The dairy side is the Milk vocabulary (§1.5).
צ'יזבורגר names both and is a direct kosher term.

### 9.4 Alcohol (halal)

| Term | Meaning | Use |
|---|---|---|
| יין, בירה, וודקה, רום, ליקר, מירין, ברנדי, קוניאק, סאקה, ויסקי, וויסקי, ערק, שמפניה, מרסלה, טקילה, סנגריה, קוקטייל, אלכוהול, פלמבה | alcohol in a glass or a sauce | likely; רום takes no free prefix |
| טירמיסו, ריזוטו, טריאקי | desserts and dishes often made with alcohol | suspected |
| ללא אלכוהול, נטול/נטולת אלכוהול; חומץ יין; בירה שחורה | non-alcoholic; wine vinegar; malt beer | guards |

**"שרי" is left out on purpose:** on an Israeli menu it is the cherry
tomato (עגבניות שרי), not sherry.

### 9.5 Blood and gelatin

| Term | Meaning | Use |
|---|---|---|
| נקניק דם | blood sausage | direct (kosher and halal) |
| ג'לטין, פנקוטה, פנה קוטה, מרשמלו, סוכריות גומי | gelatin and gelatin desserts | suspected; ג'לטין lowered before דגים |

---

## 14. Hebrew menu terms for the extra diets (issue #342)

**Status: desk research, added 2026-10-21, not reviewed by a dietitian, a
rabbi, a Jain scholar or a native-speaking editor.** The diet rules are
file 11 §30 with their sources; the Hebrew words below are the app's own
menu lexicon, and no web source confirms their spellings (as §7 says of all
Hebrew dish vocabulary). Most terms are reused from other sections: meat and
poultry (§2.2), fish (§1.7), wheat and gluten grains (§1.4), legumes
(§1.3), milk (§1.5), eggs (§1.6), tree nuts (§1.2), sesame (§1.1) and
halal's alcohol (§9.4).

### 14.1 Grains, legumes and dairy (paleo, Whole30, AIP)

| Term | Meaning | Use |
|---|---|---|
| אורז, ריזוטו, פאייה, תירס, קורנפלור, פולנטה, ממליגה, פופקורן, טורטיה, נאצ'וס, שיבולת שועל, קוואקר, דייסה, גרנולה, מוזלי, קינואה, כוסמת, דוחן, סורגום, אמרנט, סובה, דגנים | rice, corn, oats and the other grains | direct |
| קמח, שניצל, נאגטס, פאי, סושי, ניגירי, טאקו, בוריטו, קסדייה, טאבולה, קובה | dishes that carry a grain | likely; מקומח, טארט, ראפ suspected |
| סאטה, טריאקי, הויסין, פונזו, קונג פאו | soy- and peanut-based sauces | likely |
| חלבי, הפוך, לאטה, קפוצ'ינו, גלידה, צזיקי, אלפרדו, בשמל, הולנדייז, פסטו, טירמיסו | dairy coffees, sauces, desserts | likely; קרמי suspected |
| גהי, סמנה, סאמנה | ghee | suspected (paleo, AIP); not a trigger for Whole30 |
| אורז כרובית, קמח שקדים, חלב שקדים/קוקוס/סויה, חמאת בוטנים/שקדים, שעועית ירוקה, חומץ אורז | look-alikes | guards (the second word lowers the first) |

### 14.2 Sugar, oils and alcohol

| Term | Meaning | Use |
|---|---|---|
| סוכר, מסוכר, קרמל, סירופ גלוקוזה, פונדנט, טופי, סוכריות | refined sugar | suspected (paleo, AIP); stated for Whole30 |
| דבש, מייפל, אגבה, סילאן, מולסה, סטיביה, ממתיק, סירופ | other sweeteners | stated for Whole30 only |
| מקורמל, מזוגג | caramelised, glazed | suspected (Whole30) |
| ברביקיו, קטשופ, חמוץ מתוק, צ'ילי מתוק | sweetened sauces | likely (Whole30) |
| קנולה, שמן צמחי, שמן חמניות, מרגרינה, טיגון עמוק | seed oils | suspected (paleo, AIP) |
| יין (and היין, ביין, ויין), יינות, וודקה, רום, ויסקי, ג'ין, טקילה, ברנדי, קוניאק, ליקר, סאקה, שמפניה, פרוסקו, סנגריה, קוקטייל, מוחיטו, ספריץ, אפרול, קמפרי, ורמוט, ערק, אוזו, לימונצ'לו, אלכוהול | alcohol | stated for Whole30 and AIP; יין and רום take no free prefix (מיין, מרום); Jain reuses §9.4 |
| מירין, מרסלה, פלמבה | alcohol in cooking | likely; מרגריטה suspected and lowered after פיצה |
| חומץ יין | wine vinegar | guard |

### 14.3 AIP: seeds, spices, nightshades, coffee

| Term | Meaning | Use |
|---|---|---|
| אגוזים, זרעים, זרעי, גרעינים, גרעיני, צ'יה, פשתן, פרג | nuts and seeds | direct |
| כמון, קימל, אניס, חרדל, מוסקט | seed spices | direct |
| קארי, זעתר, דוקה, בהרט, חוואייג', ראס אל חנות, גרם מסאלה | spice blends | likely |
| עגבנייה, עגבניות, תפוח אדמה, תפוחי אדמה, צ'יפס, חציל, חצילים, פלפל, פלפלים, גמבה, צ'ילי, פפריקה, חלפיניו, קאיין | nightshades | direct; פלפל lowered before שחור/לבן/אנגלי and after מלח; צ'יפס lowered before בטטה |
| פירה, סלסה, קטשופ, מרינרה, ארביאטה, בולונז, הריסה, סחוג, מטבוחה, באבא גנוש, רטטוי, מוסקה | tomato, pepper and potato dishes | likely; פירה lowered before בטטה/כרובית |
| קפה, אספרסו, אמריקנו, מוקה, מקיאטו, שוקולד, קקאו | coffee and chocolate | direct; נוטלה likely |

### 14.4 Jain: roots and fungi

| Term | Meaning | Use |
|---|---|---|
| בצל, בצלים, שאלוט, כרישה, כרישות | onion family | direct |
| שום (and השום, ושום, בשום, ובשום, והשום) | garlic | direct; no free prefix (משום, "because"); lowered after אין and before דבר ("any") |
| תפוח אדמה, תפוחי אדמה, צ'יפס, גזר, סלק, צנון, צנונית, לפת, בטטה, ג'ינג'ר, זנגביל, חזרת | roots and tubers | direct |
| פירה, לביבות, ניוקי, וואסאבי, צזיקי, פסטו, סלסה, צ'ימיצ'ורי | dishes built on a root | likely |
| פטריות, פטרייה, כמהין, ציר, מרק | fungi; stock and soup (onion) | suspected |
| דבש | honey | direct; lowered before תמרים (date "honey" is silan) |

### 14.5 Pescatarian: meat beyond §2.2

| Term | Meaning | Use |
|---|---|---|
| מרגז, קבנוס, צ'וריסו, מעורב ירושלמי | sausages, Jerusalem mixed grill | direct |
| כבד, כבדים, קציצות, עראייס, קרפצ'יו, נקניקיה | liver, meatballs, arayes, carpaccio, hot dog | likely; ציר suspected |
| סטייק טונה, המבורגר דגים, קציצות דגים, שניצל טבעוני | fish or plant versions | guards (a fish or plant word after the meat word) |

---

## Sources

Grades: **[S]** strong (official, clinical, peer-reviewed, manufacturer),
**[M]** medium (national press, hospital, patient association, platform page),
**[W]** weak (blog, recipe, forum, vendor, dated).

### Israeli epidemiology
- [S] https://cris.huji.ac.il/en/publications/food-allergy-is-a-matter-of-geography-after-all-sesame-as-a-major/ — Dalal 2002, sesame in Israeli infants
- [S] https://cris.huji.ac.il/en/publications/sesame-is-a-major-cause-of-severe-ige-mediated-food-allergic-reac/
- [S] https://cris.tau.ac.il/en/publications/the-sesame-peanut-conundrum-in-israel-reevaluation-of-food-allerg/ — Garkaby 2020
- [S] https://www.aaaai.org/Tools-for-the-Public/Latest-Research-Summaries/The-Journal-of-Allergy-and-Clinical-Immunology-In/2020/foodall
- [S] https://allergysite.co.il/wp-content/uploads/2022/12/Bamba-2008-1.pdf — Du Toit 2008 PDF
- [M] https://www.confectionerynews.com/Article/2008/11/07/Early-peanut-exposure-may-reduce-chances-of-allergy-Study/
- [S] https://pmc.ncbi.nlm.nih.gov/articles/PMC4416404/ — LEAP
- [M] https://medreview.odus.princeton.edu/2025/06/23/bamba-babies-how-one-snack-revolutionized-global-understanding-of-peanut-allergies
- [M] https://www.tasmc.org.il/bewell/interestareas/kid/alerg-kids/
- [S] https://www.ima.org.il/MedicineIMAJ/Article.aspx?aId=252 — celiac in conscripts
- [S] https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5051084/ — celiac, Bedouin
- [W] https://itongadol.com/?p=100454
- [M] https://www.ynet.co.il/health/article/H1JLwoYNu
- [S] https://fs.knesset.gov.il/globaldocs/MMM/fd516b58-e9f7-e411-80c8-00155d010977/2_fd516b58-e9f7-e411-80c8-00155d010977_11_10337.pdf
- [S] https://cris.bgu.ac.il/en/publications/frequency-of-lct-13910ct-and-lct-22018ga-single-nucleotide-polymo-3/ — lactase genotypes
- [S] https://pubmed.ncbi.nlm.nih.gov/28690131/ — Storhaug 2017
- [M] https://www.clalit.co.il/he/medical/medical_diagnosis/Pages/lactose_intolerance.aspx
- [M] https://www.tasmc.org.il/health/gastro/lactase-paper/
- [S] https://cris.tau.ac.il/en/publications/early-exposure-to-cows-milk-protein-is-protective-against-ige-med/ — Katz 2010
- [M] https://www.dairyreporter.com/Article/2013/05/30/Misdiagnosed-cow-s-milk-allergy-in-infants-potentially-harmful/

### Israeli allergen sources by food
- [M] https://allergy.org.il/אלרגיה-לשומשום/
- [M] https://allergy.org.il/אלרגיה-קטניות/
- [M] https://www.allergy.org.il/סלרי/
- [M] https://www.allergyisrael.org.il/אלרגנים-נפוצים/ — Yahel
- [M] https://www.allergyisrael.org.il/about/
- [W] https://www.rdm.co.il/food-allergy/
- [M] https://www.e-med.co.il/indications/pediatric-nutrition/2022/10/12/544113
- [W] https://www.focus.co.il/page/קטניות-ללא-תהיות
- [M] https://he.wikipedia.org/wiki/בוטן
- [M] https://he.wikipedia.org/wiki/אלרגיה_לאגוזים
- [M] https://allergynet.co.il/אלרגיה-למזון/אלרגיה-לאגוזים/
- [W] http://ek.meydalle.info/kalfon212.htm
- [S] https://www.osem-nestle.co.il/brands/במבה/חטיף-במבה-קלאסית
- [S] https://www.osem-nestle.co.il/brands/במבה/חטיף-במבה-במילוי-קרם-נוגט-אריזה-גדולה
- [S] https://www.osem-nestle.co.il/brands/אסם/פתיתים-ותוספות/פתיתים-אפויים-אסם-אורז
- [S] https://www.sheba.co.il/general/nutrition-guides/nutrition-for-celiac
- [M] https://www.maccabi4u.co.il/maccabi_circles/healthy-and-tasty/celiac_disease/
- [M] https://www.szmc.org.il/departments/wilf-childrens-hospital/hamachon-legastro-yeladim-vetzuna/tzuna-vebeayot-sigsug-beyeladim/dgeshim-tzunatieim/
- [M] https://www.leumit.co.il/nutrition/celiac-nutrition-without-gluten/
- [W] https://www.foodsdictionary.co.il/articles/1519
- [W] https://barili.biz/2019/12/05/מותר-ואסור-תזונה-ללא-גלוטן/
- [W] https://derech-hatavlinim.co.il/product/רוטב-סויה-תמרי-1-ליטר/
- [W] https://shkedionet.co.il/product/פריכיות-אורז-בצ'ילי/
- [M] https://he.wikipedia.org/wiki/ג'חנון
- [M] https://he.wikipedia.org/wiki/כובאנה
- [W] https://momflavours.co.il/melt-in-your-mouth-malawach-recipe/
- [M] https://he.wikipedia.org/wiki/פלאפל
- [W] https://www.mako.co.il/food-weekend/falafel-hakosem/Article-24b9ad2f82a7351006.htm
- [W] https://taimeta.co.il/falafel-making-spoon-recipe/
- [W] https://gilacooking.co.il/green-fava-falafel-recipe/
- [W] https://www.bishulim.co.il/מתכון/סביח-חצילים-וביצה-קשה
- [W] https://www.10dakot.co.il/recipe/סביח/
- [W] https://www.krutit.co.il/סלט-חצילים-בטחינה-ומיונז/
- [W] https://www.mako.co.il/food-holiday-recipes/passover/Recipe-e693fe140dad681026.htm
- [W] https://www.hidabroot.org/article/1226396 — bourekas with sesame
- [W] https://www.matkonzikaron.co.il/dairy-recipe/בורקס-גבינה-ותפוח-אדמה
- [W] https://foody.co.il/foody_recipe/בורקס-במלית-גבינה-וזיתים/
- [M] https://blog.beok.co.il/article/15482/ — egg
- [W] https://selected-recipes.com/q-41/
- [W] https://mayatzur.com/2020/03/11/השמות-השונים-שאלרגנים-יכולים-להופיע-ע/
- [W] https://www.hashulchan.co.il/topic/חריימה/
- [M] https://www.haaretz.co.il/food/recipes/2022-09-18/ty-article-recipe/00000183-50e8-d6c6-afe7-f7e8ea2c0000
- [W] https://sweetscent.co.il/shrimp-kosher-halacha/
- [W] https://www.hidabroot.org/question/17740
- [M] https://he.wikipedia.org/wiki/אלרגיה_לחרדל
- [M] https://he.wikipedia.org/wiki/אלרגיה_לסלרי
- [M] https://www.mako.co.il/health-illnesses-and-medicines/illnesses/Article-6ca7db1f3dfac51006.htm
- [M] https://www.ynet.co.il/article/4620823 — sulphites in dried fruit
- [M] https://allergynet.co.il/פריחה/אלרגיה-למזון/רגישות-לסולפיטים/
- [S] https://www.allergy.org.au/images/pc/ASCIA_PC_Dietary_Guide_Shellfish_Alllergy_2023.pdf

### Kosher, vegan and label conventions
- [S] https://oukosher.org/blog/consumer-kosher/kashrus-and-allergens/
- [M] https://en.wikipedia.org/wiki/Pareve
- [M] https://www.neocate.com/blog/kosher-foods-milk-allergies
- [M] https://www.maariv.co.il/news/health/article-1285408 — MoH: pareve/vegan may contain milk protein
- [M] https://www.israelhayom.co.il/health/article/19915266
- [M] https://www.jdn.co.il/health/2585511/
- [M] https://www.mako.co.il/health-news/Article-2acaf49ae276c91026.htm
- [M] https://www.inn.co.il/news/690093
- [M] https://ph.yhb.org.il/17-38-04/ — mehadrin
- [W] https://zestyburger.co.il/kosher-mehadrin-vs-regular/
- [W] https://dietmaya.substack.com/p/e5f — "ללא סוכר" threshold
- [W] https://www.hidabroot.org/article/1226391
- [M] https://www.ynet.co.il/health/article/SyRdRSYLu — Osher Deri case

### Kosher and halal Hebrew terms (§9; checked 2026-10-21, snippets only)
- [M] https://en.wikipedia.org/wiki/White_meat — "white meat" is the Israeli euphemism for pork
- [M] https://forward.com/articles/105658 — *basar lavan*, *stek lavan* on menus
- [M] https://www.thejc.com/life/food/how-the-holy-land-got-a-pork-habit-uzc8a7su
- [W] https://newvoices.org/2010/10/03/israeli-bacon/
- [W] https://jewishpress.com/review/in-print-review/hebrew-lingo/2020/11/26

### Israeli regulation and platforms
- [S] https://tazkirim.gov.il/s/legislativeworkactivity/a133Y00000K4MkhQAF/הפצה-להערות-ציבור?language=en_US — 2022 draft
- [S] https://www.gov.il/BlobFolder/generalpage/allergens-guidance/he/files_publications_units_food_control_services_allergens-guidance.pdf — MoH guide v2, 29 Jun 2025
- [S] https://www.gov.il/BlobFolder/reports/fcs-110912825/he/files_publications_units_food_control_services_fcs-110912825.pdf
- [S] https://www.gov.il/BlobFolder/rfp/cfb-852/he/files_invitation-to-tender_cfb-852.pdf
- [S] https://fs.knesset.gov.il/globaldocs/MMM/17e5347d-18b6-e611-80ca-00155d020699/2_17e5347d-18b6-e611-80ca-00155d020699_11_7007.pdf
- [S] https://fs.knesset.gov.il/globaldocs/MMM/2cbd8d55-f7f7-e411-80c8-00155d010977/2_2cbd8d55-f7f7-e411-80c8-00155d010977_11_7308.pdf
- [M] https://www.chamber.org.il/foreigntrade/1109/1110/136721/
- [M] https://www.maariv.co.il/news/health/article-1245520
- [M] https://www.ice.co.il/consumerism/news/article/1088607
- [M] https://www.ynet.co.il/economy/article/sj51hea0ex
- [M] https://www.kikar.co.il/news/food-allergen-labeling-reform
- [M] https://www.teamfrance-export.fr/infos-sectorielles/39650/39650-nouvelles-obligations-detiquetage-des-allergenes
- [M] https://www.freyrsolutions.com/consumer-industry-news/israel-proposes-alignment-of-food-labelling-rules-with-eu-regulation-11692011
- [W] https://www.bar-oncohen.co.il/essays/index.php?action=9.html
- [M] https://www.israelhayom.co.il/article/871289 — EpiPen bill
- [M] https://www.themarker.com/news/health/2021-04-20/ty-article/.premium/0000017f-dc12-db5a-a57f-dc7aaed60000
- [M] https://www.aroma.co.il/מידע-תזונתי-ואזהרות/
- [M] https://www.mcdonalds.co.il/מהפיכת_התזונה/מידע_בדבר_אלרגנים
- [M] https://www.ynet.co.il/articles/0,7340,L-4968865,00.html — celiac restaurant seal (2017)
- [W] https://www.rest.co.il/kosher-restaurants/israel/kosher/allergy-awareness/
- [W] https://www.alergim.com/מסעדות-מומלצות-לאלרגים-במרכז
- [W] https://www.wheatout.co.il/מדריך-הצליאק-הטוב-בישראל/
- [M] https://wolt.com/en/isr/tel-aviv/category/gluten-free
- [M] https://wolt.com/en/isr/tel-aviv/discovery/category-vegan
- [M] https://wolt.com/en/isr/tel-aviv/restaurant/tandoori-herzeliya/items/vegan-dishes-12
- [M] https://explore.wolt.com/en/deu/terms
- [M] https://www.10bis.co.il/next/Restaurants/Menu/Delivery/3620/זה%20סושי
- [M] https://www.10bis.co.il/next/Restaurants/Menu/Delivery/24585/פילאף%20פוד%20בר%20אוכל%20מוכן

### US
- [S] https://www.foodallergy.org/resources/dining-out
- [S] https://www.foodallergy.org/living-food-allergy/food-allergy-essentials/common-allergens/peanut
- [S] https://www.foodallergy.org/fare-blog/fare-patient-registry-data-sheds-light-prevention-and-management-food-allergy-reactions
- [S] https://www.foodallergy.org/media/634/download — FARE, Traveling to Mexico
- [M] https://www.spokin.com/hidden-allergens
- [M] https://www.spokin.com/ordering-by-allergen
- [M] https://www.spokin.com/egg-allergy-friendly-asian-restaurant-guide
- [M] https://www.spokin.com/sesame-allergy-friendly-asian-restaurant-guide
- [S] https://celiac.org/dining-and-social-eating/
- [S] https://celiac.org/gluten-free-living/what-is-gluten/sources-of-gluten/
- [S] https://celiac.org/2023/06/28/traveling-gluten-free/
- [S] https://bidmc.org/-/media/files/bidmc/digestive-care/celiac-center/educational-materials/nutrition/bidmc-dining-out-travel-tips-celiac-disease.pdf
- [M] https://icds.p.asnevents.com.au/days/2026-11-20/abstract/139049
- [M] https://community.kidswithfoodallergies.org/blog/new-california-bill-would-require-allergen-labeling-on-restaurant-menus
- [M] https://community.kidswithfoodallergies.org/blog/young-advocates-propel-bill-forward-to-label-food-allergens-on-restaurant-menus
- [M] https://community.kidswithfoodallergies.org/blog/milk-allergy-alert-mcdonald-s-fried-chicken-items
- [M] https://community.kidswithfoodallergies.org/blog/reminder-restaurant-foods-may-have-different-ingredients-by-region
- [M] https://kidswithfoodallergies.org/living-with-food-allergies/top-food-allergens/milk-allergy/
- [M] https://www.foodservicedirector.com/operations/4-hidden-sources-allergens
- [W] https://support.gringostexmex.com/hc/en-us/articles/360034344433-I-am-a-vegetarian-vegan-what-items-should-I-avoid
- [W] https://www.wyndly.com/blogs/learn/pesto-allergy
- [W] https://italyplanner.com/italy-allergies-guide-dining.html
- [W] https://www.hellofresh.ca/recipes/classic-turkey-meatballs-6829eb1d99bb603b9b4386e6
- [W] https://www.partstown.com/about-us/seafood-allergies-in-restaurants
- [W] https://www.allergyhome.org/handbook/daily-life-with-food-allergies/restaurants
