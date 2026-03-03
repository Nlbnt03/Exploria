class SignUpProfile {
  const SignUpProfile({
    required this.name,
    required this.surname,
    required this.username,
    required this.email,
  });

  final String name;
  final String surname;
  final String username;
  final String email;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'surname': surname,
      'username': username,
      'email': email,
    };
  }

  factory SignUpProfile.fromJson(Map<String, dynamic> json) {
    return SignUpProfile(
      name: (json['name'] ?? '') as String,
      surname: (json['surname'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      email: (json['email'] ?? '') as String,
    );
  }
}
