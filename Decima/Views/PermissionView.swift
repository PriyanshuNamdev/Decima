import SwiftUI

struct PermissionView: View {
    var allowAction: () -> Void
    var denyAction: () -> Void
    
    var body: some View {
        ZStack {
            Color.nearBlack.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.coralRed)
                        Text("Decima")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
//                    Image(systemName: "gearshape")
//                        .foregroundColor(.lightGray)
//                        .font(.system(size: 20))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                Spacer()
                
                // Images illustration
                HStack(spacing: 12) {
                    VStack(spacing: 12) {
                        Image("Image_Ex_1")
                            .font(.system(size: 40))
                            .foregroundColor(.lightGray)
                            .frame(width: 100, height: 100)
                            .background(Color.deepBrownBlack)
                            .cornerRadius(16)
                        
                        Image("Image_Ex_2")
                            .font(.system(size: 40))
                            .foregroundColor(.lightGray)
                            .frame(width: 96, height: 85)
                            .background(Color.deepBrownBlack)
                            .cornerRadius(16)
                    }
                    
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 40))
                            .foregroundColor(.coralRed)
                        
                        VStack(spacing: 8) {
                            Image(systemName: "lock")
                                .font(.system(size: 20))
                                .foregroundColor(.lightGray)
                            Text("Only on device")
                                .font(.system(size: 12))
                                .foregroundColor(.lightGray)
                        }
                    }
                    .frame(width: 140, height: 212)
                    .background(Color.deepBrownBlack)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.charcoalBorder, lineWidth: 1)
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 24) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your memories.")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Text("Your permission.")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Subtitle
                    Text("Decima needs access to Photos to help you find screenshots, videos and extra copies.")
                        .font(.system(size: 16))
                        .foregroundColor(.lightGray)
                        .lineSpacing(4)
                    
                    // Checkmarks
                    VStack(alignment: .leading, spacing: 20) {
                        bulletItem(icon: "checkmark.shield", title: "Private by design", description: "Photos are reviewed on this device.")
                        bulletItem(icon: "checkmark", title: "You stay in control", description: "Nothing is deleted without your approval.")
                    }
                    
                    // Info Box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.lightGray)
                            .font(.system(size: 16))
                        Text("Choose Full Access in the iOS prompt to browse your whole library. Limited Access shows only the photos you allow.")
                            .font(.system(size: 13))
                            .foregroundColor(.lightGray)
                            .lineSpacing(2)
                    }
                    .padding(16)
                    .background(Color.deepBrownBlack)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Bottom Buttons
                VStack(spacing: 16) {
                    Button(action: allowAction) {
                        Text("Allow photo library access")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.primaryGradient)
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func bulletItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(.coralRed)
                .font(.system(size: 20))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.lightGray)
            }
        }
    }
}
