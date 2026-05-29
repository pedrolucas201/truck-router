const String googleMapsApiKey = 'AIzaSyBTuVg56cUrhb04TqC4emC01zn4FvsSwt4';
const String backendUrl      = String.fromEnvironment('BACKEND_URL');
const String backendApiKey   = String.fromEnvironment('BACKEND_API_KEY');

Map<String, String> get backendHeaders => {'X-Api-Key': backendApiKey};
