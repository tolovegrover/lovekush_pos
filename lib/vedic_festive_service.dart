import 'package:flutter/material.dart';

/// Represents an Indian Festive or Vrat occasion with retail demand insights.
class VedicFestivalEvent {
  final String id;
  final String name;
  final String hindiName;
  final String type; // "त्यौहार" (Festival), "महापर्व" (Grand Festival), "व्रत" (Fasting), "जयंती" (Jayanti)
  final String tithiDescription; // e.g. "श्रावण शुक्ल तृतीया"
  final int approxMonth; // 1-12
  final int approxDay;   // 1-31
  final String topSellingItemsHindi; // e.g. "हरी चूड़ियां, मेहंदी कोन, लहरिया दुपट्टा"
  final String topSellingItemsEnglish; // e.g. "Green Bangles, Mehendi Cones, Leheriya Dupatta"
  final String distributorAdvice; // Retail advice for shopkeeper
  final double demandMultiplier; // e.g. 3.5x
  final IconData icon;
  final List<String> searchKeywords;

  const VedicFestivalEvent({
    required this.id,
    required this.name,
    required this.hindiName,
    required this.type,
    required this.tithiDescription,
    required this.approxMonth,
    required this.approxDay,
    required this.topSellingItemsHindi,
    required this.topSellingItemsEnglish,
    required this.distributorAdvice,
    required this.demandMultiplier,
    required this.icon,
    required this.searchKeywords,
  });

  /// Calculate the next upcoming calendar date for this occasion
  DateTime nextOccurrence(DateTime from) {
    var candidate = DateTime(from.year, approxMonth, approxDay);
    if (candidate.isBefore(DateTime(from.year, from.month, from.day))) {
      candidate = DateTime(from.year + 1, approxMonth, approxDay);
    }
    return candidate;
  }

  /// Number of days remaining until this festival
  int daysRemaining(DateTime from) {
    final next = nextOccurrence(from);
    final today = DateTime(from.year, from.month, from.day);
    return next.difference(today).inDays;
  }

  /// Whether today is the day of this festival
  bool isToday(DateTime from) {
    return daysRemaining(from) == 0;
  }
}

/// Comprehensive service for Indian retail festivals, vrats, and retail stocking insights
class VedicFestiveService {
  /// Master list of 32+ Hindu retail festivals, vrats, and high-demand occasions
  static const List<VedicFestivalEvent> allFestivals = [
    // 1. Hariyali Teej
    VedicFestivalEvent(
      id: "hariyali_teej",
      name: "Hariyali Teej",
      hindiName: "हरियाली तीज (छोटी तीज)",
      type: "त्यौहार",
      tithiDescription: "श्रावण शुक्ल तृतीया",
      approxMonth: 8,
      approxDay: 7,
      topSellingItemsHindi: "हरी कांच की चूड़ियां, लहरिया दुपट्टा, मेहंदी कोन, सुहाग पिटारी, बिंदी, काजल, लिपस्टिक, नेलपेंट, हेयर क्लिप, पायल",
      topSellingItemsEnglish: "Green Bangles, Leheriya Dupatta, Mehendi Cones, Shringar Box, Bindi, Kajal, Lipsticks, Nail Polish, Hair Accessories",
      distributorAdvice: "तीज से 2-3 हफ्ते पहले हरी चूड़ियों व मेहंदी का भारी स्टॉक रखें। तीज से 2 दिन पहले महिलाओं की भारी भीड़ उमड़ती है।",
      demandMultiplier: 3.8,
      icon: Icons.grass,
      searchKeywords: ["bangle", "churi", "mehendi", "green", "shringar", "bindi", "kajal", "lipstick"],
    ),

    // 2. Shri Krishna Janmashtami
    VedicFestivalEvent(
      id: "janmashtami",
      name: "Shri Krishna Janmashtami",
      hindiName: "श्री कृष्ण जन्माष्टमी",
      type: "महापर्व",
      tithiDescription: "भाद्रपद कृष्ण अष्टमी",
      approxMonth: 8,
      approxDay: 26,
      topSellingItemsHindi: "लड्डू गोपाल जी की मूर्तियां, कान्हा पोशाक व वस्त्र, बांसुरी (Flute), मुकुट, मोर पंख, झूला (Palna/Jhula), चंदन, अगरबत्ती, पूजा थाली, इत्र (Perfume)",
      topSellingItemsEnglish: "Laddoo Gopal Idols, Krishna Poshak & Dresses, Flute (Bansuri), Crown (Mukut), Peacock Feather (Mor Pankh), Jhula/Cradle, Chandan, Ittar, Pooja Thali",
      distributorAdvice: "लड्डू गोपाल के वस्त्र (0 से 6 नंबर), पालने और बांसुरी 1 महीना पहले मंगवाएं। हर परिवार कान्हा जी के नए वस्त्र खरीदता है!",
      demandMultiplier: 4.2,
      icon: Icons.child_care,
      searchKeywords: ["poshak", "krishna", "laddoo gopal", "bansuri", "flute", "mukut", "jhula", "mor pankh", "ittar", "chandan"],
    ),

    // 3. Bhadra Teej / Kajari Teej
    VedicFestivalEvent(
      id: "kajari_teej",
      name: "Kajari Teej / Bhadra Teej",
      hindiName: "कजरी तीज (भाद्रपद बड़ी तीज / सातुड़ी तीज)",
      type: "त्यौहार",
      tithiDescription: "भाद्रपद कृष्ण तृतीया",
      approxMonth: 8,
      approxDay: 21,
      topSellingItemsHindi: "रंग-बिरंगी चूड़ियां, कंगन, मेहंदी कोन, सिन्दूर, बिछिया, सजने-संवरने का सामान, सत्तू पूजा सामग्री, सुहाग पिटारी",
      topSellingItemsEnglish: "Colorful Glass Bangles, Kangans, Mehendi Cones, Sindoor, Bichhiya, Cosmetics Makeup Kits, Sattu Puja Items, Suhag Boxes",
      distributorAdvice: "हरियाली तीज के ठीक 15 दिन बाद आती है। कांच की चूड़ियां, मेहंदी और बिंदी का काउंटर रिस्टॉक रखें।",
      demandMultiplier: 3.4,
      icon: Icons.favorite,
      searchKeywords: ["bangle", "churi", "kangan", "mehendi", "sindoor", "makeup", "bichhiya"],
    ),

    // 4. Ganesh Chaturthi
    VedicFestivalEvent(
      id: "ganesh_chaturthi",
      name: "Ganesh Chaturthi (Vinayaka Chavithi)",
      hindiName: "श्री गणेश चतुर्थी (गणेशोत्सव)",
      type: "महापर्व",
      tithiDescription: "भाद्रपद शुक्ल चतुर्थी",
      approxMonth: 9,
      approxDay: 7,
      topSellingItemsHindi: "श्री गणेश जी की मूर्तियां (Ganesh Idols), मोदक मोल्ड/सांचे, लाल चुनरी, पूजा चौकी, सजावटी माला, धूप-दीप, कपूर, रोली-अक्षत, पीतल की घंटी",
      topSellingItemsEnglish: "Ganesh Idols (Clay/Eco-friendly), Modak Moulds, Red Chunri, Decorative Pooja Chowki, Garlands, Dhoop, Kapoor, Roli-Akshat, Pooja Bells",
      distributorAdvice: "10 दिवसीय गणेशोत्सव हेतु गणेश जी की प्रतिमाएं, मोदक के सांचे और धूप-दीप का बड़ा फ्रंट डिस्प्ले बनाएं।",
      demandMultiplier: 4.0,
      icon: Icons.temple_hindu,
      searchKeywords: ["ganesh", "idol", "murti", "modak", "chunri", "dhoop", "kapoor", "puja", "garland"],
    ),

    // 5. Hartalika Teej
    VedicFestivalEvent(
      id: "hartalika_teej",
      name: "Hartalika Teej",
      hindiName: "हरतालिका तीज",
      type: "व्रत",
      tithiDescription: "भाद्रपद शुक्ल तृतीया",
      approxMonth: 9,
      approxDay: 6,
      topSellingItemsHindi: "मिट्टी के शिव-पार्वती-गणेश जी, हरी व पीली चूड़ियां, सोलह श्रृंगार किट, मेहंदी, आलता, सिन्दूर, कंगन, व्रत कथा पुस्तक",
      topSellingItemsEnglish: "Clay Shiva-Parvati-Ganesh Idols, Green & Yellow Bangles, 16 Shringar Kit, Mehendi, Alta, Sindoor, Kangans, Vrat Katha Books",
      distributorAdvice: "सुहागन महिलाएं 24 घंटे का निर्जल व्रत रखती हैं। सोलह श्रृंगार पिटारी व आलता का सबसे ज्यादा उठाव होता है।",
      demandMultiplier: 3.7,
      icon: Icons.auto_awesome,
      searchKeywords: ["shringar", "alta", "sindoor", "bangle", "mehendi", "churi", "shiva"],
    ),

    // 6. Karwa Chauth
    VedicFestivalEvent(
      id: "karwa_chauth",
      name: "Karwa Chauth",
      hindiName: "करवा चौथ (करक चतुर्थी)",
      type: "व्रत",
      tithiDescription: "कार्तिक कृष्ण चतुर्थी",
      approxMonth: 10,
      approxDay: 20,
      topSellingItemsHindi: "करवा (Karwa Pot), छलनी (Sieve), दुल्हन चूड़ा, कांच की चूड़ियां, मेहंदी कोन, बिंदी, सिन्दूर, नेलपेंट, करवा थाली, लाल चुनरी, फेशियल किट, लिपस्टिक",
      topSellingItemsEnglish: "Karwa Pots, Chalni (Sieve), Bridal Chooda, Glass Bangles, Mehendi Cones, Bindi, Sindoor, Nail Enamels, Karwa Thali, Red Chunri, Facial Kits",
      distributorAdvice: "कॉस्मेटिक्स और चूड़ियों की साल की सबसे बड़ी बिक्री! 1 महीना पहले से तैयारी करें; करवा थाली व छलनी 3 हफ्ते पहले सजाएं।",
      demandMultiplier: 5.0,
      icon: Icons.nightlight_round,
      searchKeywords: ["karwa", "chalni", "chooda", "bangle", "sindoor", "mehendi", "facial", "lipstick", "thali"],
    ),

    // 7. Ahoi Ashtami
    VedicFestivalEvent(
      id: "ahoi_ashtami",
      name: "Ahoi Ashtami",
      hindiName: "अहोई अष्टमी",
      type: "व्रत",
      tithiDescription: "कार्तिक कृष्ण अष्टमी",
      approxMonth: 10,
      approxDay: 24,
      topSellingItemsHindi: "अहोई माता कैलेंडर/फोटो, स्याऊ माला (चांदी के दाने व कलावा धागा), रोली, काजल, सिन्दूर, पूजा दीये, ड्राई फ्रूट्स",
      topSellingItemsEnglish: "Ahoi Mata Calendar/Poster, Syau Mala (Silver beads & red thread), Roli, Kajal, Sindoor, Pooja Diyas, Dry Fruits",
      distributorAdvice: "संतान की दीर्घायु का व्रत। अहोई माता के कैलेंडर और स्याऊ माला धागे 10 दिन पहले स्टॉक करें।",
      demandMultiplier: 2.8,
      icon: Icons.stars,
      searchKeywords: ["ahoi", "calendar", "syau", "mala", "dhaga", "kajal", "sindoor", "roli"],
    ),

    // 8. Dhanteras & Diwali
    VedicFestivalEvent(
      id: "diwali",
      name: "Dhanteras & Diwali Festival",
      hindiName: "धनतेरस एवं दीपावली महापर्व",
      type: "महापर्व",
      tithiDescription: "कार्तिक कृष्ण त्रयोदशी से अमावस्या",
      approxMonth: 11,
      approxDay: 1,
      topSellingItemsHindi: "लक्ष्मी-गणेश जी की मूर्तियां, मिट्टी व पीतल के दीये, सजावटी लाइटें, परफ्यूम, गिफ्ट हैंपर्स, ड्राई फ्रूट बॉक्स, प्रीमियम कॉस्मेटिक्स, रंगोली रंग",
      topSellingItemsEnglish: "Lakshmi-Ganesh Idols, Clay & Brass Diyas, Decorative Lights, Perfumes, Gift Hampers, Dry Fruit Boxes, Premium Cosmetics, Rangoli Colors",
      distributorAdvice: "वर्ष का सर्वोच्च टर्नओवर! 15 अक्टूबर तक दुकान को गिफ्ट हैंपर्स, परफ्यूम और लक्ष्मी-गणेश पूजन सामग्री से पूरी तरह भर लें।",
      demandMultiplier: 5.0,
      icon: Icons.light_mode,
      searchKeywords: ["diya", "diwali", "lakshmi", "ganesh", "gift", "perfume", "rangoli", "light", "hamper"],
    ),

    // 9. Govardhan Puja & Bhai Dooj
    VedicFestivalEvent(
      id: "bhai_dooj",
      name: "Govardhan Puja & Bhai Dooj",
      hindiName: "गोवर्धन पूजा एवं भाई दूज",
      type: "त्यौहार",
      tithiDescription: "कार्तिक शुक्ल प्रतिपदा व द्वितीया",
      approxMonth: 11,
      approxDay: 3,
      topSellingItemsHindi: "रोली-चावल कार्ड, भाई दूज गिफ्ट हैंपर्स, परफ्यूम, रुमाल, शेविंग किट, कॉस्मेटिक्स गिफ्ट पैक, मिठाई डिब्बे, खील-बताशे",
      topSellingItemsEnglish: "Roli-Chawal Cards, Bhai Dooj Gift Hampers, Men's Perfumes, Handkerchiefs, Shaving Kits, Sister Gift Cosmetics, Mithai Boxes",
      distributorAdvice: "दिवाली के तुरंत बाद भाई दूज गिफ्टिंग रश आता है। पुरुषों के ग्रूमिंग किट व गिफ्ट हैंपर्स काउंटर पर रखें।",
      demandMultiplier: 3.2,
      icon: Icons.card_giftcard,
      searchKeywords: ["bhai dooj", "gift", "roli", "perfume", "shaving", "grooming", "hamper"],
    ),

    // 10. Chhath Puja
    VedicFestivalEvent(
      id: "chhath_puja",
      name: "Chhath Puja",
      hindiName: "सूर्य षष्ठी महापर्व (छठ पूजा)",
      type: "महापर्व",
      tithiDescription: "कार्तिक शुक्ल षष्ठी",
      approxMonth: 11,
      approxDay: 7,
      topSellingItemsHindi: "बांस का सूप, दौरा, पीला व नारंगी सिन्दूर, आलता, पीली/लाल साड़ियां, नारियल, पूजा सामग्री, मिट्टी के दीये, कच्ची हल्दी",
      topSellingItemsEnglish: "Bamboo Soop, Daura Baskets, Yellow/Orange Sindoor, Alta, Yellow/Red Sarees, Coconuts, Pooja Samagri, Clay Diyas, Raw Turmeric",
      distributorAdvice: "पूर्वांचल व बिहार समुदाय का महापर्व। सूप, दौरा, आलता और नारंगी सिन्दूर 2 हफ्ते पहले मंगवा लें।",
      demandMultiplier: 4.5,
      icon: Icons.wb_sunny,
      searchKeywords: ["chhath", "soop", "daura", "orange sindoor", "alta", "saree", "coconut", "diya"],
    ),

    // 11. Devutthana Ekadashi & Tulsi Vivah
    VedicFestivalEvent(
      id: "tulsi_vivah",
      name: "Devutthana Ekadashi & Tulsi Vivah",
      hindiName: "देवउठनी एकादशी एवं तुलसी विवाह",
      type: "व्रत",
      tithiDescription: "कार्तिक शुक्ल एकादशी",
      approxMonth: 11,
      approxDay: 12,
      topSellingItemsHindi: "तुलसी जी का श्रृंगार, लाल चुनरी, हरी व लाल चूड़ियां, रोली, कलावा, गन्ने की पूजा सामग्री, शादी सीजन की शुरुआत का सामान",
      topSellingItemsEnglish: "Tulsi Shringar, Red Chunri, Bangles, Roli, Kalava, Sugarcane Puja Items, Wedding Season Starter Items",
      distributorAdvice: "चातुर्मास समाप्ति व शादियों की शुरुआत का दिन! तुलसी जी के श्रृंगार और शादी की चूड़ियों की भारी मांग होती है।",
      demandMultiplier: 3.2,
      icon: Icons.yard,
      searchKeywords: ["tulsi", "vivah", "ekadashi", "chunri", "bangle", "wedding", "sugarcane"],
    ),

    // 12. Makar Sankranti
    VedicFestivalEvent(
      id: "makar_sankranti",
      name: "Makar Sankranti & Pongal",
      hindiName: "मकर संक्रांति एवं पोंगल",
      type: "त्यौहार",
      tithiDescription: "माघ संक्रांति (सौर)",
      approxMonth: 1,
      approxDay: 14,
      topSellingItemsHindi: "पतंग (Kites), मांझा (Manjha string), तिल-गुड़ के डिब्बे, दान-पुण्य के वस्त्र, गिफ्ट हैंपर, तिल पापड़ी",
      topSellingItemsEnglish: "Kites, Cotton Manjha Strings, Til-Gud Sweets Boxes, Donation Clothes, Winter Gift Hampers",
      distributorAdvice: "पतंग व मांझा दिसंबर अंत में ही स्टॉक करें। संक्रांति से 3 दिन पहले पतंगबाजी की जबरदस्त बिक्री होती है।",
      demandMultiplier: 2.8,
      icon: Icons.air,
      searchKeywords: ["kite", "patang", "manjha", "til", "gud", "sankranti"],
    ),

    // 13. Vasant Panchami & Saraswati Puja
    VedicFestivalEvent(
      id: "vasant_panchami",
      name: "Vasant Panchami & Saraswati Puja",
      hindiName: "वसंत पंचमी एवं सरस्वती पूजा",
      type: "त्यौहार",
      tithiDescription: "माघ शुक्ल पञ्चमी",
      approxMonth: 2,
      approxDay: 2,
      topSellingItemsHindi: "पीले वस्त्र/कुर्ते, पीली चुनरी, मां सरस्वती पूजा सामग्री, पीले हेयर क्लिप/बैंड, पेन-कॉपी स्टेशनरी, पीली बिंदी",
      topSellingItemsEnglish: "Yellow Clothes/Kurtas, Yellow Chunri, Saraswati Puja Items, Yellow Hair Clips/Bands, Stationery, Yellow Bindi",
      distributorAdvice: "पीले रंग के दुपट्टे, बिंदी और हेयर एक्सेसरीज 10 दिन पहले फ्रंट रैक पर सजाएं।",
      demandMultiplier: 2.6,
      icon: Icons.menu_book,
      searchKeywords: ["yellow", "saraswati", "panchami", "chunri", "clip", "hair", "bindi"],
    ),

    // 14. Maha Shivratri
    VedicFestivalEvent(
      id: "maha_shivratri",
      name: "Maha Shivratri",
      hindiName: "महाशिवरात्रि महापर्व",
      type: "महापर्व",
      tithiDescription: "फाल्गुन कृष्ण चतुर्दशी",
      approxMonth: 2,
      approxDay: 26,
      topSellingItemsHindi: "बेलपत्र, धतूरा, रुद्राक्ष माला, शिवलिंग वस्त्र, पीतल का लोटा (Jalpatra), भस्म/विभूति, कपूर, धूप-अगरबत्ती, फलाहारी सामग्री",
      topSellingItemsEnglish: "Belpatra, Dhatura, Rudraksha Mala, Shivling Cloths, Brass Jalpatra (Lota), Bhasma, Camphor, Dhoop, Fasting Foods",
      distributorAdvice: "पीतल के लोटे, धूप-दीप और रुद्राक्ष का पर्याप्त स्टॉक रखें। शिवभक्तों की सुबह से शाम तक भीड़ रहती है।",
      demandMultiplier: 3.6,
      icon: Icons.circle,
      searchKeywords: ["shiv", "shiva", "rudraksha", "lota", "jalpatra", "kapoor", "dhoop", "bhasma"],
    ),

    // 15. Holi & Rangwali
    VedicFestivalEvent(
      id: "holi",
      name: "Holi & Rangwali Festival",
      hindiName: "होली महापर्व एवं धुलंडी",
      type: "महापर्व",
      tithiDescription: "फाल्गुन पूर्णिमा",
      approxMonth: 3,
      approxDay: 14,
      topSellingItemsHindi: "हर्बल गुलाल, पिचकारी (Pichkari), पानी के गुब्बारे, नारियल तेल, सरसों तेल, फेस क्लींजर, स्किन शील्ड क्रीम, वाइट टी-शर्ट",
      topSellingItemsEnglish: "Herbal Gulal, Water Guns (Pichkari), Water Balloons, Coconut Hair Oil, Mustard Oil, Face Cleansers, White T-Shirts",
      distributorAdvice: "गुलाल व पिचकारी 3 हफ्ते पहले मंगवाएं। होली से 2 दिन पहले बाल व त्वचा सुरक्षा हेतु नारियल तेल का बंपर उठाव होता है।",
      demandMultiplier: 4.5,
      icon: Icons.color_lens,
      searchKeywords: ["gulal", "color", "pichkari", "balloon", "coconut oil", "hair oil", "cleanser", "holi"],
    ),

    // 16. Chaitra Navratri & Hindu Nav Varsh
    VedicFestivalEvent(
      id: "chaitra_navratri",
      name: "Chaitra Navratri & Hindu New Year",
      hindiName: "चैत्र नवरात्रि एवं हिन्दू नव वर्ष (विक्रम संवत्)",
      type: "महापर्व",
      tithiDescription: "चैत्र शुक्ल प्रतिपदा से नवमी",
      approxMonth: 3,
      approxDay: 30,
      topSellingItemsHindi: "माता की लाल चुनरी, नारियल, कलश, अखंड ज्योति, रोली, सिन्दूर, कपूर, हवन सामग्री, व्रत कुट्टू/सिंघाड़ा आटा",
      topSellingItemsEnglish: "Mata Red Chunri, Coconuts, Kalash, Akhand Jyot, Roli, Sindoor, Kapoor, Hawan Samagri, Vrat Atta",
      distributorAdvice: "नव वर्ष व चैत्र नवरात्रि हेतु चुनरी, रोली, कपूर और अखंड ज्योति का फ्रंट डिस्प्ले बनाएं।",
      demandMultiplier: 3.5,
      icon: Icons.wb_twilight,
      searchKeywords: ["navratri", "chunri", "kalash", "jyot", "coconut", "roli", "sindoor", "kapoor"],
    ),

    // 17. Shri Ram Navami
    VedicFestivalEvent(
      id: "ram_navami",
      name: "Shri Ram Navami",
      hindiName: "श्री राम नवमी",
      type: "त्यौहार",
      tithiDescription: "चैत्र शुक्ल नवमी",
      approxMonth: 4,
      approxDay: 6,
      topSellingItemsHindi: "श्री राम दरबार पोशाक, केसरिया ध्वज (झंडे), पूजा थाली, मुकुट, पुष्प माला, अगरबत्ती, चंदन",
      topSellingItemsEnglish: "Ram Darbar Poshak, Saffron Flags (Dhwaj), Pooja Thali, Mukut, Flower Garlands, Incense Sticks, Chandan",
      distributorAdvice: "केसरिया झंडे (राम ध्वज) और पूजा सामग्री 10 दिन पहले मंगाएं। शोभायात्राओं में भारी मांग रहती है।",
      demandMultiplier: 3.0,
      icon: Icons.flag,
      searchKeywords: ["ram", "dhwaj", "flag", "poshak", "thali", "mukut", "chandan"],
    ),

    // 18. Hanuman Janmotsav
    VedicFestivalEvent(
      id: "hanuman_jayanti",
      name: "Shri Hanuman Janmotsav",
      hindiName: "श्री हनुमान जन्मोत्सव (जयंती)",
      type: "जयंती",
      tithiDescription: "चैत्र पूर्णिमा",
      approxMonth: 4,
      approxDay: 12,
      topSellingItemsHindi: "चोला सिन्दूर (चमेली तेल व सिन्दूर), लाल लंगोट/वस्त्र, गदा (Gada), लाल ध्वज, अगरबत्ती, कपूर, रोली",
      topSellingItemsEnglish: "Chola Sindoor (Jasmine oil & vermillion), Red Langot/Cloths, Hanuman Gada, Red Flags, Agarbatti, Camphor",
      distributorAdvice: "हनुमान जी के चोला सिन्दूर और चमेली के तेल का बहुत बड़ा उठाव होता है।",
      demandMultiplier: 3.0,
      icon: Icons.fitness_center,
      searchKeywords: ["hanuman", "chola", "sindoor", "jasmine oil", "dhwaj", "gada", "kapoor"],
    ),

    // 19. Vat Savitri Vrat
    VedicFestivalEvent(
      id: "vat_savitri",
      name: "Vat Savitri Vrat",
      hindiName: "वट सावित्री व्रत",
      type: "व्रत",
      tithiDescription: "ज्येष्ठ अमावस्या",
      approxMonth: 5,
      approxDay: 26,
      topSellingItemsHindi: "बरगद पूजा का कच्चा सूत (सफेद व पीला धागा), बांस का पंखा (Hand Fan), लाल बिंदी, कांच की चूड़ियां, सिन्दूर, सोलह श्रृंगार पिटारी",
      topSellingItemsEnglish: "Vat Puja Raw Cotton Thread (Soot), Bamboo Hand Fan, Red Bindi, Glass Bangles, Sindoor, 16 Shringar Kit",
      distributorAdvice: "कच्चा सूत धागा, बांस का पंखा और चूड़ियां 1 हफ्ते पहले फ्रंट काउंटर पर रखें।",
      demandMultiplier: 3.2,
      icon: Icons.park,
      searchKeywords: ["soot", "dhaga", "fan", "bangle", "churi", "bindi", "sindoor", "shringar"],
    ),

    // 20. Nirjala Ekadashi
    VedicFestivalEvent(
      id: "nirjala_ekadashi",
      name: "Nirjala Ekadashi",
      hindiName: "निर्जला एकादशी (भीमसेनी एकादशी)",
      type: "व्रत",
      tithiDescription: "ज्येष्ठ शुक्ल एकादशी",
      approxMonth: 6,
      approxDay: 6,
      topSellingItemsHindi: "मिट्टी का घड़ा (Matka/Surahi), हाथ का पंखा, जल सेवा पात्र, शर्बत के पैकेट, फलाहारी सामग्री, लड्डू गोपाल जी का भोग",
      topSellingItemsEnglish: "Clay Water Pots (Matka), Hand Fans, Water Service Bowls, Sharbat Syrups, Fasting Foods, Laddoo Gopal Bhog",
      distributorAdvice: "साल की सबसे बड़ी एकादशी। दान-पुण्य हेतु घड़ा, पंखा और शर्बत की भारी मांग होती है।",
      demandMultiplier: 3.0,
      icon: Icons.water_drop,
      searchKeywords: ["ekadashi", "nirjala", "matka", "fan", "sharbat", "laddoo gopal"],
    ),

    // 21. Jagannath Rath Yatra
    VedicFestivalEvent(
      id: "rath_yatra",
      name: "Jagannath Rath Yatra",
      hindiName: "जगन्नाथ रथ यात्रा",
      type: "महापर्व",
      tithiDescription: "आषाढ़ शुक्ल द्वितीया",
      approxMonth: 6,
      approxDay: 27,
      topSellingItemsHindi: "प्रभु जगन्नाथ-बलभद्र-सुभद्रा जी की पोशाक, छोटे लकड़ी के रथ, तुलसी माला, चंदन, अगरबत्ती, पूजा थाली",
      topSellingItemsEnglish: "Jagannath-Balabhadra-Subhadra Poshak, Miniature Wooden Chariots (Rath), Tulsi Mala, Chandan, Dhoop",
      distributorAdvice: "रथ यात्रा के अवसर पर जगन्नाथ जी के वस्त्र और छोटे रथ बच्चों के लिए खूब बिकते हैं।",
      demandMultiplier: 2.7,
      icon: Icons.directions_bus,
      searchKeywords: ["jagannath", "rath", "poshak", "tulsi mala", "chandan"],
    ),

    // 22. Guru Purnima
    VedicFestivalEvent(
      id: "guru_purnima",
      name: "Guru Purnima",
      hindiName: "गुरु पूर्णिमा (व्यास पूर्णिमा)",
      type: "त्यौहार",
      tithiDescription: "आषाढ़ पूर्णिमा",
      approxMonth: 7,
      approxDay: 10,
      topSellingItemsHindi: "शॉल, पीले/सफेद वस्त्र, चरण पादुका, श्रीफल (नारियल), माला, उपहार गिफ्ट पैक, पेन व डायरी",
      topSellingItemsEnglish: "Shawls, Yellow/White Kurtas, Charan Paduka, Coconuts, Garlands, Guru Gift Hampers, Diaries & Pens",
      distributorAdvice: "गुरु पूजन हेतु शॉल, नारियल और गिफ्ट हैंपर्स 1 हफ्ता पहले सजाएं।",
      demandMultiplier: 2.5,
      icon: Icons.person,
      searchKeywords: ["guru", "purnima", "shawl", "paduka", "coconut", "gift"],
    ),

    // 23. Shravan Maas & Sawan Somwar
    VedicFestivalEvent(
      id: "sawan_somwar",
      name: "Shravan Maas & Sawan Somwar",
      hindiName: "पवित्र श्रावण मास एवं सावन सोमवार",
      type: "व्रत",
      tithiDescription: "सम्पूर्ण श्रावण मास",
      approxMonth: 7,
      approxDay: 22,
      topSellingItemsHindi: "हरी कांच की चूड़ियां (Green Bangles), हरी साड़ियां/सूट, मेहंदी कोन, कांवड़ सजावट, रुद्राक्ष, पीतल का जल लोटा, चंदन, अगरबत्ती",
      topSellingItemsEnglish: "Green Glass Bangles, Green Suits/Sarees, Mehendi Cones, Kanwar Decorations, Rudraksha, Brass Lota, Chandan, Agarbatti",
      distributorAdvice: "सावन शुरू होने से पहले हरी कांच की चूड़ियों व मेहंदी के कार्टन भर लें। पूरे महीने निरंतर मांग रहती है।",
      demandMultiplier: 3.5,
      icon: Icons.water,
      searchKeywords: ["sawan", "shravan", "bangle", "churi", "green", "mehendi", "lota", "rudraksha"],
    ),

    // 24. Raksha Bandhan
    VedicFestivalEvent(
      id: "raksha_bandhan",
      name: "Raksha Bandhan",
      hindiName: "रक्षाबंधन महापर्व",
      type: "महापर्व",
      tithiDescription: "श्रावण पूर्णिमा",
      approxMonth: 8,
      approxDay: 9,
      topSellingItemsHindi: "डिजाइनर राखियां, बच्चों की कार्टून/लाइट वाली राखी, रोली-चावल कार्ड, सिस्टर गिफ्ट पैक, कॉस्मेटिक्स किट, चॉकलेट डिब्बे, रुमाल",
      topSellingItemsEnglish: "Designer Rakhis, Kids Cartoon/LED Rakhis, Roli-Chawal Cards, Sister Gift Packs, Cosmetics Kits, Chocolate Boxes",
      distributorAdvice: "राखी का स्टॉक 1 महीना पहले (15 जुलाई तक) मंगवाएं। रक्षाबंधन से 5 दिन पहले भारी फुटफॉल होता है।",
      demandMultiplier: 4.8,
      icon: Icons.loyalty,
      searchKeywords: ["rakhi", "raksha bandhan", "sister gift", "roli", "cosmetics kit", "chocolate"],
    ),

    // 25. Sharad Navratri & Durga Puja
    VedicFestivalEvent(
      id: "sharad_navratri",
      name: "Sharad Navratri & Durga Puja",
      hindiName: "शारदीय नवरात्रि एवं दुर्गा पूजा",
      type: "महापर्व",
      tithiDescription: "आश्विन शुक्ल प्रतिपदा से नवमी",
      approxMonth: 10,
      approxDay: 3,
      topSellingItemsHindi: "माता की चुनरी, डांडिया स्टिक्स, फेस्टिव मेकअप (आईलाइनर, लिपस्टिक, काजल, कॉम्पैक्ट), बिंदी, चूड़ियां, हेयर एक्सेसरीज, ज्वैलरी",
      topSellingItemsEnglish: "Mata Chunri, Dandiya Sticks, Festive Makeup (Eyeliner, Lipstick, Compact), Bindi, Bangles, Hair Accessories, Artificial Jewelry",
      distributorAdvice: "डांडिया और नवरात्रि के 9 दिनों हेतु कॉस्मेटिक्स, वाटरप्रूफ आईलाइनर व आर्टिफिशियल ज्वैलरी का भारी स्टॉक रखें।",
      demandMultiplier: 4.2,
      icon: Icons.celebration,
      searchKeywords: ["navratri", "dandiya", "chunri", "makeup", "lipstick", "eyeliner", "bindi", "bangle"],
    ),

    // 26. Vijaya Dashami (Dussehra)
    VedicFestivalEvent(
      id: "dussehra",
      name: "Vijaya Dashami (Dussehra)",
      hindiName: "विजयादशमी (दशहरा महापर्व)",
      type: "महापर्व",
      tithiDescription: "आश्विन शुक्ल दशमी",
      approxMonth: 10,
      approxDay: 12,
      topSellingItemsHindi: "खिलौना अस्त्र-शस्त्र (धनुष-बाण/तलवार), रावण दहन खिलौने, जलेबी डब्बे, वाहन पूजा माला व रिबन, अगरबत्ती",
      topSellingItemsEnglish: "Toy Bow-Arrows & Swords, Miniature Ravan Toys, Jalebi Boxes, Vehicle Pooja Garlands & Ribbons",
      distributorAdvice: "दशहरे पर बच्चों के धनुष-बाण और नई गाड़ियों की पूजा माला व नीले रिबन की भारी मांग होती है।",
      demandMultiplier: 3.0,
      icon: Icons.military_tech,
      searchKeywords: ["dussehra", "bow", "arrow", "garland", "vehicle", "jalebi"],
    ),

    // 27. Sharad Purnima
    VedicFestivalEvent(
      id: "sharad_purnima",
      name: "Sharad Purnima (Raas Purnima)",
      hindiName: "शरद पूर्णिमा (कोजागरी पूर्णिमा / रास पूर्णिमा)",
      type: "त्यौहार",
      tithiDescription: "आश्विन पूर्णिमा",
      approxMonth: 10,
      approxDay: 17,
      topSellingItemsHindi: "खीर के पात्र, सफेद वस्त्र/पोशाक, चांदी के वर्क, ड्राई फ्रूट्स, पूजा थाली, दीपक, कपूर",
      topSellingItemsEnglish: "Kheer Serving Bowls, White Kurtas/Dresses, Silver Leaves, Dry Fruits, Pooja Thali, Deepaks",
      distributorAdvice: "अमृत वर्षा की रात! खीर बनाने के बर्तन, ड्राई फ्रूट्स और सफेद वस्त्रों की मांग रहती है।",
      demandMultiplier: 2.5,
      icon: Icons.circle_outlined,
      searchKeywords: ["kheer", "sharad purnima", "white", "dry fruit", "diya"],
    ),

    // 28. Monthly Ekadashi Vrats
    VedicFestivalEvent(
      id: "monthly_ekadashi",
      name: "Monthly Ekadashi Vrats",
      hindiName: "हर महीने के एकादशी व्रत (शुक्ल व कृष्ण)",
      type: "व्रत",
      tithiDescription: "प्रत्येक माह की 11वीं तिथि (महीने में 2 बार)",
      approxMonth: 9,
      approxDay: 22,
      topSellingItemsHindi: "फलाहारी सामग्री (कुट्टू, सिंघाड़ा, साबूदाना), लड्डू गोपाल जी का भोग, अगरबत्ती, कपूर, तुलसी माला",
      topSellingItemsEnglish: "Falahari Items (Kuttu, Sabudana, Dry Fruits), Laddoo Gopal Bhog, Incense Sticks, Camphor, Tulsi Mala",
      distributorAdvice: "महीने में 2 बार एकादशी आती है। फलाहार और कान्हा जी के भोग सामग्री का नियमित स्टॉक रखें।",
      demandMultiplier: 2.2,
      icon: Icons.spa,
      searchKeywords: ["ekadashi", "vrat", "sabudana", "kuttu", "laddoo gopal", "kapoor"],
    ),

    // 29. Monthly Pradosh Vrat
    VedicFestivalEvent(
      id: "monthly_pradosh",
      name: "Monthly Pradosh Vrats",
      hindiName: "प्रदोष व्रत (शिव त्रयोदशी)",
      type: "व्रत",
      tithiDescription: "प्रत्येक माह की त्रयोदशी (सायंकाल)",
      approxMonth: 9,
      approxDay: 24,
      topSellingItemsHindi: "शिव पूजा सामग्री, पीतल का लोटा, कच्चा दूध पात्र, दीपक, धूपबत्ती, कपूर, बेलपत्र",
      topSellingItemsEnglish: "Shiva Puja Samagri, Brass Jal Lota, Raw Milk Pots, Deepaks, Dhoop, Camphor",
      distributorAdvice: "प्रदोष काल में शिव पूजन हेतु दीपक, धूप और पूजा पात्र की निरंतर बिक्री होती है।",
      demandMultiplier: 2.0,
      icon: Icons.water_drop_outlined,
      searchKeywords: ["pradosh", "shiva", "lota", "diya", "dhoop", "kapoor"],
    ),

    // 30. Winter Wedding Season
    VedicFestivalEvent(
      id: "winter_wedding",
      name: "Winter Wedding Season (Lagun)",
      hindiName: "शीतकालीन विवाह सीजन (शादी-ब्याह)",
      type: "त्यौहार",
      tithiDescription: "कार्तिक से पौष (विवाह मुहूर्त)",
      approxMonth: 11,
      approxDay: 20,
      topSellingItemsHindi: "ब्राइडल मेकअप, फाउंडेशन, कंसीलर, आईलैशेज, हेयर स्प्रे, आर्टिफिशियल ब्राइडल ज्वैलरी, दुल्हन चूड़ा, परफ्यूम",
      topSellingItemsEnglish: "Bridal Makeup Kits, Foundations, Concealers, Eyelashes, Hair Sprays, Artificial Jewelry, Bridal Chooda, Perfumes",
      distributorAdvice: "नवंबर से दिसंबर तक शादियों का पीक रश! ब्राइडल कॉस्मेटिक्स और हेयर स्प्रे का बैकअप स्टॉक रखें।",
      demandMultiplier: 4.5,
      icon: Icons.diversity_1,
      searchKeywords: ["wedding", "bridal", "chooda", "foundation", "jewelry", "eyelashes", "perfume"],
    ),

    // 31. Winter Skincare Peak
    VedicFestivalEvent(
      id: "winter_skincare",
      name: "Winter Skincare Peak Season",
      hindiName: "सर्दियों की स्किनकेयर एवं त्वचा सुरक्षा",
      type: "त्यौहार",
      tithiDescription: "मार्गशीर्ष से माघ (शीत ऋतु)",
      approxMonth: 12,
      approxDay: 15,
      topSellingItemsHindi: "कोल्ड क्रीम (Pond's Cold Cream), बॉडी लोशन (Nivea / Vaseline), पेट्रोलियम जेली, लिप बाम, ग्लिसरीन, गुलाब जल",
      topSellingItemsEnglish: "Cold Creams (Pond's), Body Lotions (Nivea/Vaseline), Petroleum Jelly, Lip Balms, Glycerin, Rose Water",
      distributorAdvice: "सर्दियों में 100ml व 200ml बॉडी लोशन और कोल्ड क्रीम के थोक कार्टन काउंटर के सामने रखें।",
      demandMultiplier: 3.5,
      icon: Icons.ac_unit,
      searchKeywords: ["cold cream", "body lotion", "vaseline", "lip balm", "glycerin", "nivea", "ponds"],
    ),

    // 32. Summer Peak & Prickly Heat
    VedicFestivalEvent(
      id: "summer_rush",
      name: "Summer Rush & Sun Protection",
      hindiName: "ग्रीष्मकालीन दैनिक उत्पाद एवं धूप सुरक्षा",
      type: "त्यौहार",
      tithiDescription: "वैशाख से ज्येष्ठ (ग्रीष्म ऋतु)",
      approxMonth: 5,
      approxDay: 1,
      topSellingItemsHindi: "घमौरियों का पाउडर (Dermicool / Nycil), कूलिंग टेलकम, डियोड्रेंट, सनस्क्रीन (SPF 30/50), फेस वाइप्स, एलोवेरा जेल",
      topSellingItemsEnglish: "Prickly Heat Powders (Dermicool/Nycil), Cooling Talcs, Deodorants, Sunscreens SPF 30/50, Wet Wipes, Aloe Vera Gel",
      distributorAdvice: "गर्मी में कूलिंग टेलकम पाउडर और सनस्क्रीन की बहुत तेज बिक्री होती है; काउंटर बास्केट में रखें।",
      demandMultiplier: 3.0,
      icon: Icons.wb_sunny_outlined,
      searchKeywords: ["dermicool", "nycil", "talc", "powder", "deodorant", "sunscreen", "wipes"],
    ),
  ];

  /// Get festivals sorted by upcoming occurrence from a given date
  static List<VedicFestivalEvent> getUpcomingFestivals(DateTime from) {
    final list = List<VedicFestivalEvent>.from(allFestivals);
    list.sort((a, b) => a.nextOccurrence(from).compareTo(b.nextOccurrence(from)));
    return list;
  }

  /// Get the single next upcoming major festival
  static VedicFestivalEvent? getNextEvent(DateTime from) {
    final sorted = getUpcomingFestivals(from);
    return sorted.isNotEmpty ? sorted.first : null;
  }

  /// Find if today or within next [daysWindow] days there is a festive event
  static List<VedicFestivalEvent> getImminentFestivals(DateTime from, {int daysWindow = 7}) {
    final sorted = getUpcomingFestivals(from);
    return sorted.where((ev) => ev.daysRemaining(from) <= daysWindow).toList();
  }

  /// Search festivals by keyword, name, or product category
  static List<VedicFestivalEvent> searchFestivals(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return allFestivals;

    return allFestivals.where((ev) {
      if (ev.name.toLowerCase().contains(q)) return true;
      if (ev.hindiName.toLowerCase().contains(q)) return true;
      if (ev.topSellingItemsHindi.toLowerCase().contains(q)) return true;
      if (ev.topSellingItemsEnglish.toLowerCase().contains(q)) return true;
      if (ev.tithiDescription.toLowerCase().contains(q)) return true;
      if (ev.searchKeywords.any((k) => k.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }
}
