import SwiftUI

struct CategoryCardView: View {
    let category: MediaCategory
    let count: Int
    let sizeString: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: category.iconSystemName)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.coralRed)
                    .frame(width: 32, height: 32, alignment: .leading)
                
                Spacer()
                
                Text(sizeString.isEmpty ? "--" : sizeString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.lightGray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.softWhite)
                    .lineLimit(1)
                
                Text(count > 0 ? "\(count) items" : "--")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.softWhite)
                
                Text(category.subtitlePlaceholder)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.mutedDarkGray)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(Color.warmCharcoal)
        .cornerRadius(16)
    }
}
