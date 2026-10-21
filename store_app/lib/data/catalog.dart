import '../models/content.dart';
import '../models/product.dart';

// بيانات تجريبية يكدر صاحب المتجر يضيفها من لوحة التحكم بضغطة.
// معرّفات الأقسام نفس اللي استخدمتها المنتجات القديمة حتى تبقى مربوطة.

const sampleCategories = <Category>[
  Category(id: 'gifts', name: 'هدايا', iconKey: 'gift', order: 1),
  Category(id: 'flowers', name: 'ورود', iconKey: 'flower', order: 2),
  Category(id: 'perfume', name: 'عطور', iconKey: 'resin', order: 3),
  Category(id: 'sweets', name: 'حلويات', iconKey: 'heart', order: 4),
];

const sampleProducts = <Product>[
  Product(
    name: 'بوكس هدية فاخر',
    description: 'بوكس مرتب بيه شموع وشوكولاتة وكارت إهداء باسم الشخص.',
    price: 35000,
    categoryId: 'gifts',
  ),
  Product(
    name: 'ساعة يد كلاسيك',
    description: 'ساعة أنيقة بتغليف هدية، تنفع للمناسبات.',
    price: 60000,
    categoryId: 'gifts',
  ),
  Product(
    name: 'باقة ورد جوري',
    description: 'باقة ورد جوري أحمر طبيعي، 12 وردة.',
    price: 25000,
    categoryId: 'flowers',
  ),
  Product(
    name: 'سلة ورد مشكل',
    description: 'سلة ورد بألوان مختلفة مع شريطة.',
    price: 40000,
    categoryId: 'flowers',
  ),
  Product(
    name: 'عطر عود',
    description: 'عطر عود شرقي، 100 مل.',
    price: 45000,
    categoryId: 'perfume',
  ),
  Product(
    name: 'عطر ورد',
    description: 'عطر نسائي برائحة الورد، 50 مل.',
    price: 30000,
    categoryId: 'perfume',
  ),
  Product(
    name: 'كيكة مناسبات',
    description: 'كيكة بالاسم والتاريخ اللي تريده، تكفي 8 أشخاص.',
    price: 28000,
    categoryId: 'sweets',
  ),
  Product(
    name: 'علبة شوكولاتة',
    description: 'شوكولاتة بلجيكية مشكلة، 24 قطعة.',
    price: 20000,
    categoryId: 'sweets',
  ),
];
