import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
struct BrandPageView: View {
    let brandName: String
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            Text("Brand \(brandName) Products")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding()
            
            Divider()
                .padding(.horizontal)
            
            // Brand Info Section
            VStack(alignment: .leading, spacing: 15) {
                Text("Brand Details")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                InfoRow(label: "Brand Name", value: brandName)
                InfoRow(label: "Status", value: "Active")
                InfoRow(label: "Category", value: "Products")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Placeholder for products
            VStack(spacing: 10) {
                Text("Available Products")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ForEach(1...3, id: \.self) { index in
                    ProductRow(productName: "\(brandName) Product \(index)")
                }
            }
            .padding()
            
            Spacer()
        }
        .navigationTitle(brandName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct ProductRow: View {
    let productName: String
    
    var body: some View {
        HStack {
            Image(systemName: "cube.box.fill")
                .foregroundColor(.blue)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(productName)
                    .font(.body)
                    .fontWeight(.medium)
                Text("In Stock")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 2)
    }
}

@available(iOS 14.0, macOS 11.0, *)
#Preview {
    NavigationView {
        BrandPageView(brandName: "Fat Tire")
    }
}
