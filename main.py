import kivy
kivy.require('2.3.0')

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.spinner import Spinner
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.uix.button import Button
from datetime import datetime
import json
import requests
import os

import arabic_reshaper
from bidi.algorithm import get_display

def reshape_ar(text):
    return get_display(arabic_reshaper.reshape(text))

# بيانات بوت تليجرام
BOT_TOKEN = '7528010802:AAEyZkLxRbFQFdKew8x3cQ7Ci1rrOfVUciI'
CHAT_ID = '-1002246411153'

BOOKING_FILE = "bookings.json"
ARABIC_FONT = 'Amiri-Regular.ttf'  # تأكد من وجود الخط بجانب ملف البرنامج

class BookingForm(BoxLayout):
    def __init__(self, **kwargs):
        super().__init__(orientation='vertical', padding=10, spacing=10, **kwargs)

        self.inputs = {}

        self.inputs['name'] = TextInput(
            hint_text=reshape_ar('اسم الزبون'),
            halign='right',
            font_name=ARABIC_FONT
        )
        self.inputs['phone'] = TextInput(
            hint_text=reshape_ar('رقم الهاتف'),
            halign='right',
            input_filter='int',
            font_name=ARABIC_FONT
        )
        self.inputs['address'] = TextInput(
            hint_text=reshape_ar('عنوان الزبون'),
            halign='right',
            multiline=False,
            font_name=ARABIC_FONT
        )
        self.inputs['delivery_day'] = Spinner(
            text=reshape_ar('اختر يوم التسليم'),
            values=[reshape_ar(day) for day in ['السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة']],
            size_hint=(1, None),
            height=44,
            font_name=ARABIC_FONT
        )
        self.inputs['pickup_method'] = Spinner(
            text=reshape_ar('طريقة الاستلام'),
            values=[reshape_ar(method) for method in ['توصيل', 'استلام من المحل']],
            size_hint=(1, None),
            height=44,
            font_name=ARABIC_FONT
        )
        self.inputs['details'] = TextInput(
            hint_text=reshape_ar('تفاصيل الطلب'),
            halign='right',
            multiline=True,
            font_name=ARABIC_FONT
        )
        self.inputs['price'] = TextInput(
            hint_text=reshape_ar('السعر الكلي'),
            halign='right',
            input_filter='float',
            font_name=ARABIC_FONT
        )

        for key in ['name', 'phone', 'address', 'delivery_day', 'pickup_method', 'details', 'price']:
            self.add_widget(self.inputs[key])

        self.submit_btn = Button(
            text=reshape_ar('إرسال الحجز'),
            size_hint=(1, None),
            height=50,
            background_color=(0.3, 0.6, 0.4, 1),
            font_name=ARABIC_FONT
        )
        self.submit_btn.bind(on_press=self.submit_booking)
        self.add_widget(self.submit_btn)

        self.status_label = Label(
            text='',
            halign='right',
            color=(1, 0, 0, 1),
            font_name=ARABIC_FONT
        )
        self.add_widget(self.status_label)

    def submit_booking(self, instance):
        name = self.inputs['name'].text.strip()
        phone = self.inputs['phone'].text.strip()
        address = self.inputs['address'].text.strip()
        delivery_day = self.inputs['delivery_day'].text.strip()
        pickup_method = self.inputs['pickup_method'].text.strip()
        details = self.inputs['details'].text.strip()
        price = self.inputs['price'].text.strip()
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        if delivery_day == reshape_ar('اختر يوم التسليم'):
            delivery_day = ''
        if pickup_method == reshape_ar('طريقة الاستلام'):
            pickup_method = ''

        if not all([name, phone, address, delivery_day, pickup_method, details, price]):
            self.status_label.text = reshape_ar("يرجى تعبئة جميع الحقول")
            self.status_label.color = (1, 0, 0, 1)
            return

        if not (phone.startswith("07") and len(phone) == 11 and phone.isdigit()):
            self.status_label.text = reshape_ar("رقم الهاتف يجب أن يبدأ بـ 07 ويتكون من 11 رقمًا")
            self.status_label.color = (1, 0, 0, 1)
            return

        try:
            float(price)
        except ValueError:
            self.status_label.text = reshape_ar("السعر غير صالح")
            self.status_label.color = (1, 0, 0, 1)
            return

        booking = {
            'اسم الزبون': name,
            'رقم الهاتف': phone,
            'عنوان الزبون': address,
            'موعد التسليم': delivery_day,
            'طريقة الاستلام': pickup_method,
            'تفاصيل الطلب': details,
            'السعر الكلي': price,
            'تاريخ الحجز': timestamp
        }

        self.status_label.text = reshape_ar("جارٍ إرسال الحجز...")
        self.status_label.color = (1, 0.5, 0, 1)

        self.save_booking(booking)

        if self.send_to_telegram(booking):
            self.status_label.color = (0, 1, 0, 1)
            self.status_label.text = reshape_ar("تم إرسال الحجز بنجاح ✅")
            for key in self.inputs:
                if isinstance(self.inputs[key], TextInput):
                    self.inputs[key].text = ''
                elif isinstance(self.inputs[key], Spinner):
                    if key == 'delivery_day':
                        self.inputs[key].text = reshape_ar('اختر يوم التسليم')
                    elif key == 'pickup_method':
                        self.inputs[key].text = reshape_ar('طريقة الاستلام')
        else:
            self.status_label.color = (1, 0, 0, 1)
            self.status_label.text = reshape_ar("فشل في الإرسال إلى تليجرام ❌")

    def save_booking(self, booking):
        bookings = []
        if os.path.exists(BOOKING_FILE):
            with open(BOOKING_FILE, 'r', encoding='utf-8') as f:
                try:
                    bookings = json.load(f)
                except:
                    bookings = []

        bookings.append(booking)
        with open(BOOKING_FILE, 'w', encoding='utf-8') as f:
            json.dump(bookings, f, ensure_ascii=False, indent=2)

    def send_to_telegram(self, booking):
        message = "\n".join([f"*{key}*: {value}" for key, value in booking.items()])
        url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
        data = {
            "chat_id": CHAT_ID,
            "text": message,
            "parse_mode": "Markdown"
        }
        try:
            response = requests.post(url, data=data)
            if response.status_code != 200:
                print("Telegram API Error:", response.text)
            return response.status_code == 200
        except Exception as e:
            print("Exception sending to Telegram:", e)
            return False

class GiftBookingApp(App):
    def build(self):
        return BookingForm()

if __name__ == '__main__':
    GiftBookingApp().run()
