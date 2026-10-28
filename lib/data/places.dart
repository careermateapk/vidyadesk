import 'dart:convert';

import 'package:http/http.dart' as http;

/// Indian states / union territories with their main districts and cities.
/// "Other" lets people type a place that is not in the list.
const Map<String, List<String>> indiaPlaces = {
  'Andaman and Nicobar Islands': ['Port Blair', 'Car Nicobar'],
  'Andhra Pradesh': ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Nellore', 'Kurnool', 'Tirupati', 'Kakinada', 'Rajahmundry', 'Kadapa', 'Anantapur', 'Eluru', 'Ongole'],
  'Arunachal Pradesh': ['Itanagar', 'Naharlagun', 'Pasighat', 'Tawang', 'Ziro'],
  'Assam': ['Guwahati', 'Dibrugarh', 'Silchar', 'Jorhat', 'Tezpur', 'Nagaon', 'Tinsukia', 'Bongaigaon', 'Dhubri'],
  'Bihar': ['Patna', 'Gaya', 'Bhagalpur', 'Muzaffarpur', 'Darbhanga', 'Madhubani', 'Samastipur', 'Purnia', 'Saharsa', 'Begusarai', 'Arrah', 'Bihar Sharif', 'Chapra', 'Sitamarhi', 'Motihari', 'Bettiah', 'Hajipur', 'Katihar', 'Munger', 'Supaul', 'Siwan', 'Nalanda', 'Rohtas', 'Aurangabad', 'Buxar', 'Jehanabad', 'Nawada', 'Kishanganj', 'Araria', 'Madhepura', 'Khagaria', 'Gopalganj', 'Vaishali', 'Sheohar', 'Jamui', 'Lakhisarai', 'Sheikhpura', 'Banka', 'Kaimur', 'Arwal'],
  'Chandigarh': ['Chandigarh'],
  'Chhattisgarh': ['Raipur', 'Bhilai', 'Bilaspur', 'Korba', 'Durg', 'Rajnandgaon', 'Raigarh', 'Jagdalpur', 'Ambikapur'],
  'Dadra and Nagar Haveli and Daman and Diu': ['Silvassa', 'Daman', 'Diu'],
  'Delhi': ['New Delhi', 'North Delhi', 'South Delhi', 'East Delhi', 'West Delhi', 'Central Delhi', 'Dwarka', 'Rohini', 'Shahdara'],
  'Goa': ['Panaji', 'Margao', 'Vasco da Gama', 'Mapusa', 'Ponda'],
  'Gujarat': ['Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Bhavnagar', 'Jamnagar', 'Gandhinagar', 'Junagadh', 'Anand', 'Bharuch', 'Mehsana', 'Morbi', 'Navsari', 'Valsad'],
  'Haryana': ['Gurugram', 'Faridabad', 'Panipat', 'Ambala', 'Hisar', 'Karnal', 'Rohtak', 'Sonipat', 'Yamunanagar', 'Panchkula', 'Bhiwani', 'Sirsa', 'Rewari'],
  'Himachal Pradesh': ['Shimla', 'Mandi', 'Solan', 'Dharamshala', 'Kullu', 'Hamirpur', 'Una', 'Bilaspur', 'Chamba'],
  'Jammu and Kashmir': ['Srinagar', 'Jammu', 'Anantnag', 'Baramulla', 'Udhampur', 'Kathua', 'Sopore'],
  'Jharkhand': ['Ranchi', 'Jamshedpur', 'Dhanbad', 'Bokaro', 'Deoghar', 'Hazaribagh', 'Giridih', 'Ramgarh', 'Dumka', 'Palamu', 'Godda', 'Sahibganj'],
  'Karnataka': ['Bengaluru', 'Mysuru', 'Mangaluru', 'Hubballi', 'Dharwad', 'Belagavi', 'Kalaburagi', 'Davanagere', 'Ballari', 'Shivamogga', 'Tumakuru', 'Udupi', 'Vijayapura', 'Hassan'],
  'Kerala': ['Thiruvananthapuram', 'Kochi', 'Kozhikode', 'Thrissur', 'Kollam', 'Kannur', 'Alappuzha', 'Palakkad', 'Kottayam', 'Malappuram', 'Kasaragod', 'Pathanamthitta'],
  'Ladakh': ['Leh', 'Kargil'],
  'Lakshadweep': ['Kavaratti'],
  'Madhya Pradesh': ['Indore', 'Bhopal', 'Jabalpur', 'Gwalior', 'Ujjain', 'Sagar', 'Rewa', 'Satna', 'Ratlam', 'Dewas', 'Katni', 'Singrauli', 'Chhindwara', 'Khandwa', 'Morena', 'Shivpuri', 'Vidisha'],
  'Maharashtra': ['Mumbai', 'Pune', 'Nagpur', 'Thane', 'Nashik', 'Aurangabad', 'Solapur', 'Kolhapur', 'Amravati', 'Navi Mumbai', 'Akola', 'Latur', 'Jalgaon', 'Ahmednagar', 'Nanded', 'Satara', 'Sangli', 'Chandrapur', 'Ratnagiri'],
  'Manipur': ['Imphal', 'Thoubal', 'Bishnupur', 'Churachandpur'],
  'Meghalaya': ['Shillong', 'Tura', 'Jowai'],
  'Mizoram': ['Aizawl', 'Lunglei', 'Champhai'],
  'Nagaland': ['Kohima', 'Dimapur', 'Mokokchung'],
  'Odisha': ['Bhubaneswar', 'Cuttack', 'Rourkela', 'Berhampur', 'Sambalpur', 'Puri', 'Balasore', 'Bhadrak', 'Baripada', 'Jharsuguda', 'Angul'],
  'Puducherry': ['Puducherry', 'Karaikal', 'Mahe', 'Yanam'],
  'Punjab': ['Ludhiana', 'Amritsar', 'Jalandhar', 'Patiala', 'Bathinda', 'Mohali', 'Pathankot', 'Hoshiarpur', 'Moga', 'Firozpur', 'Sangrur'],
  'Rajasthan': ['Jaipur', 'Jodhpur', 'Kota', 'Bikaner', 'Ajmer', 'Udaipur', 'Bhilwara', 'Alwar', 'Sikar', 'Bharatpur', 'Sri Ganganagar', 'Pali', 'Jhunjhunu', 'Chittorgarh', 'Barmer', 'Tonk'],
  'Sikkim': ['Gangtok', 'Namchi', 'Mangan', 'Gyalshing'],
  'Tamil Nadu': ['Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli', 'Salem', 'Tirunelveli', 'Tiruppur', 'Vellore', 'Erode', 'Thoothukudi', 'Thanjavur', 'Dindigul', 'Kanchipuram', 'Nagercoil'],
  'Telangana': ['Hyderabad', 'Warangal', 'Nizamabad', 'Karimnagar', 'Khammam', 'Ramagundam', 'Mahbubnagar', 'Nalgonda', 'Adilabad', 'Siddipet'],
  'Tripura': ['Agartala', 'Udaipur', 'Dharmanagar', 'Kailashahar'],
  'Uttar Pradesh': ['Lucknow', 'Kanpur', 'Ghaziabad', 'Agra', 'Varanasi', 'Prayagraj', 'Meerut', 'Noida', 'Bareilly', 'Aligarh', 'Moradabad', 'Saharanpur', 'Gorakhpur', 'Jhansi', 'Ayodhya', 'Mathura', 'Firozabad', 'Muzaffarnagar', 'Shahjahanpur', 'Rampur', 'Ballia', 'Deoria', 'Azamgarh', 'Jaunpur', 'Mirzapur', 'Sultanpur', 'Gonda', 'Basti'],
  'Uttarakhand': ['Dehradun', 'Haridwar', 'Haldwani', 'Roorkee', 'Rudrapur', 'Kashipur', 'Rishikesh', 'Nainital', 'Almora'],
  'West Bengal': ['Kolkata', 'Howrah', 'Siliguri', 'Durgapur', 'Asansol', 'Bardhaman', 'Malda', 'Kharagpur', 'Haldia', 'Krishnanagar', 'Darjeeling', 'Jalpaiguri', 'Cooch Behar', 'Bankura', 'Purulia'],
};

List<String> get stateNames => indiaPlaces.keys.toList();

class PinResult {
  const PinResult(this.state, this.city);
  final String state, city;
}

/// Looks up a 6-digit Indian pincode (free India Post service).
/// Returns null when not found or there is no internet.
Future<PinResult?> lookupPincode(String pin) async {
  if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)) return null;
  try {
    final r = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$pin')).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final data = jsonDecode(r.body);
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is! Map || first['Status'] != 'Success') return null;
    final offices = first['PostOffice'];
    if (offices is! List || offices.isEmpty) return null;
    final o = offices.first as Map;
    final state = _matchState((o['State'] ?? '').toString());
    final city = (o['District'] ?? '').toString();
    if (state.isEmpty) return null;
    return PinResult(state, city);
  } catch (_) {
    return null;
  }
}

String _matchState(String s) {
  final low = s.toLowerCase().trim();
  for (final k in indiaPlaces.keys) {
    if (k.toLowerCase() == low) return k;
  }
  if (low.contains('delhi')) return 'Delhi';
  if (low.contains('jammu')) return 'Jammu and Kashmir';
  if (low.contains('dadra') || low.contains('daman')) return 'Dadra and Nagar Haveli and Daman and Diu';
  if (low.contains('pondicherry')) return 'Puducherry';
  return '';
}
